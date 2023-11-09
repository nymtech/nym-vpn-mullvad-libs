use futures::{
    channel::{mpsc, oneshot},
    stream::StreamExt,
};
use tokio::sync::broadcast;

// Daemon([AccessMethodSetting]) <-Crate-specific api (Set, Update)-> Actor([ApiConnectionMode]) <-Public api (Get, Rotate)-> ApiRuntime/subscribers
//                                                                      |
//                                                                      v
//                                                  ([AccessMethodSetting] -> [ApiConnectionMode])-adapter                                                                                           [ApiRuntime/subscribers]
//                                                          (Rotation strategy?)

// TODO(markus): Maybe it would be fine to make the Actor generic over the underlying
// datatype, i.e. [`AccessMethodSetting`] or [`ConnectionMode`] to accomodate
// different use cases. I.e., when we need an actor which only ever spits out
// "Direct", we don't need extra stuff with settings
pub struct ConnectionModeActor {
    inner_handle: ConnectionModeActorHandle,
    state: Box<dyn ConnectionModesIterator + Send>,
}

#[derive(Clone)]
pub struct ConnectionModeActorHandle {
    cmd_tx: mpsc::UnboundedSender<Message>,
    broadcast_sender: broadcast::Sender<Connection>,
}

type Connection = mullvad_types::access_method::AccessMethodSetting;

pub enum Message {
    /// Get the currently active [`Connection`].
    Get(ResponseTx<Connection>),
    /// Select a new active [`Connection`], invalidating the previous [`Connection`]
    Rotate(ResponseTx<()>),
    /// Ask the [`ConnectionModeActor`] to select a new active [`Connection`]
    Set(ResponseTx<()>, Connection),
    /// Update the [`Connection`]s which the actor may select a new active [`Connection`] from.
    Update(ResponseTx<()>, Box<dyn ConnectionModesIterator + Send>),
}

type Result<T> = std::result::Result<T, Error>;
type ResponseTx<T> = oneshot::Sender<Result<T>>;

#[derive(err_derive::Error, Debug)]
pub enum Error {
    /// Oddly specific.
    #[error(display = "Very Generic error.")]
    Generic,
    /// The [`ConnectionModeActor`] failed to send a reply back to the [`ConnectionModeActorHandle`].
    #[error(
        display = "ConnectionModeActor could not send message to its ConnectionModeActorHandle"
    )]
    Reply,
    /// The [`ConnectionModeActor`] has no active subscribers, but tried to brodcast updates anyway.
    /// If no one is listening, it is probably a good idea to shut down.
    #[error(display = "No one is listening for connection mode updates")]
    Broadcast(#[error(source)] broadcast::error::SendError<Connection>),
}

impl ConnectionModeActorHandle {
    pub fn handle(&self) -> Self {
        self.clone()
    }

    /// Get notified whenever a new [`Connection`] is selected.
    pub fn subscribe(&self) -> broadcast::Receiver<Connection> {
        self.broadcast_sender.subscribe()
    }

    async fn send_command<T>(&self, make_cmd: impl FnOnce(ResponseTx<T>) -> Message) -> Result<T> {
        let (tx, rx) = oneshot::channel();
        // TODO(markus): Error handling
        self.cmd_tx.unbounded_send(make_cmd(tx)).unwrap();
        // TODO(markus): Error handling
        rx.await.unwrap()
    }

    pub async fn get_access_method(&self) -> Result<Connection> {
        self.send_command(Message::Get).await.map_err(|err| {
            log::error!("Failed to get current access method!");
            err
        })
    }

    pub async fn rotate_access_method(&self) -> Result<()> {
        self.send_command(Message::Rotate).await.map_err(|err| {
            log::error!("Failed to rotate current access method!");
            err
        })
    }

    pub async fn set_access_method(&mut self, access_method: Connection) -> Result<()> {
        self.send_command(|tx| Message::Set(tx, access_method))
            .await
            .map_err(|err| {
                log::error!("Failed to set a new access method");
                err
            })
    }

    pub async fn update_access_methods(
        &mut self,
        value: Box<dyn ConnectionModesIterator + Send>,
    ) -> Result<()> {
        self.send_command(|tx| Message::Update(tx, value))
            .await
            .map_err(|err| {
                log::error!("Failed to update to new access methods");
                err
            })
    }
}

impl ConnectionModeActor {
    pub fn new(
        connection_modes: Box<dyn ConnectionModesIterator + Send>,
    ) -> ConnectionModeActorHandle {
        let (cmd_tx, cmd_rx) = mpsc::unbounded();
        let (broadcast_sender, _) = broadcast::channel::<Connection>(16); // TODO: Decide on capacity
        let handle = ConnectionModeActorHandle {
            cmd_tx,
            broadcast_sender,
        };
        tokio::spawn(
            ConnectionModeActor {
                inner_handle: handle.clone(),
                state: connection_modes,
            }
            .run(cmd_rx),
        );
        handle
    }

    async fn run(mut self, mut cmd_rx: mpsc::UnboundedReceiver<Message>) {
        // Handle incoming messages
        log::trace!("Starting a new `ConnectionModeActor` agent");
        loop {
            tokio::select! {
                cmd = cmd_rx.next() => {
                    match cmd {
                        Some(msg) => match self.handle_command(msg) {
                            Ok(_) => (),
                            Err(err) => {
                                log::info!("Error inside of [`ConnectionModeActor::run`]: {err}");
                                break
                            }
                        },
                        None => {
                            continue
                        }
                    }
                }
            }
        }
        log::info!("terminating one `ConnectionModeActor` agent");
    }

    fn handle_command(&mut self, cmd: Message) -> Result<()> {
        match cmd {
            Message::Rotate(tx) => self.on_rotate_access_method(tx),
            Message::Get(tx) => self.on_get_access_method(tx),
            Message::Set(tx, value) => self.on_set_access_method(tx, value),
            Message::Update(tx, value) => self.on_update_access_methods(tx, value),
        }
    }

    fn broadcast(&self, value: Connection) -> () {
        if self.inner_handle.broadcast_sender.send(value).is_err() {
            log::info!("No subscribers are listening for updates");
        }
    }

    fn reply<T>(&self, tx: ResponseTx<T>, value: T) -> Result<()> {
        tx.send(Ok(value)).map_err(|_| Error::Reply)
    }

    // Internal, message passing functions

    fn on_rotate_access_method(&mut self, tx: ResponseTx<()>) -> Result<()> {
        log::info!("Handling `on_rotate_current_access_method`");
        self.rotate_access_method()?;
        let new_access_method_settings = self.get_access_method();
        self.broadcast(new_access_method_settings);
        self.reply(tx, ())
    }

    fn on_get_access_method(&mut self, tx: ResponseTx<Connection>) -> Result<()> {
        log::info!("Handling `on_get_current_access_method`");
        let current_access_method = self.get_access_method();
        self.reply(tx, current_access_method)
    }

    fn on_set_access_method(&mut self, tx: ResponseTx<()>, value: Connection) -> Result<()> {
        log::info!("Handling `on_set_current_access_method`");
        self.set_access_method(value);
        self.rotate_access_method()?;
        self.reply(tx, ())
    }

    fn on_update_access_methods(
        &mut self,
        tx: ResponseTx<()>,
        value: Box<dyn ConnectionModesIterator + Send>,
    ) -> Result<()> {
        log::info!("Handling `on_update_access_methods`");
        self.state = value;
        self.reply(tx, ())
    }

    // Internal, synchronous functions

    fn rotate_access_method(&mut self) -> Result<()> {
        if let Some(next) = self.state.rotate() {
            self.broadcast(next);
        } else {
            // TODO(markus): Handle this case! Should it even be possible to not receive a next connection mode when calling `rotate`?
        };
        Ok(())
    }

    fn get_access_method(&self) -> Connection {
        self.state.peek()
    }

    fn set_access_method(&mut self, value: Connection) {
        self.state.set_access_method(value);
    }
}

/// An iterator which will always produce an [`AccessMethod`].
///
/// TODO(markus): Could it be a requirement that anything which implements [`ConnectionModesIterator`] is also an iterator?
/// Wondering if we could:
/// A. get rid of `rotate` or
/// B. get rid of the blanket implementation of [`Iterator`] for [`ConnectionModesIterator`].
pub trait ConnectionModesIterator {
    /// Set the next [`AccessMethod`] to be returned from this iterator.
    fn set_access_method(&mut self, next: Connection);
    /// Update the collection of [`AccessMethod`] which this iterator will
    /// return.
    fn update_access_methods(&mut self, access_methods: Vec<Connection>);
    /// Look at the currently active [`AccessMethod`]
    fn peek(&self) -> Connection;
    fn rotate(&mut self) -> Option<Connection>;
}

// Blanket implementation for [`Iterator`] for anything which implements
// [`ConnectionModesIterator`].
impl Iterator for dyn ConnectionModesIterator {
    type Item = Connection;

    fn next(&mut self) -> Option<Self::Item> {
        self.rotate()
    }
}

/// A useful [`ConnectionModesIterator`] which only ever returns
/// [`ConnectionMode::Direct`]
pub struct DirectConnectionModeRepeater {
    mode: Connection,
}

impl DirectConnectionModeRepeater {
    pub fn new() -> Self {
        // TODO(markus): Solve this more succintly. Perhaps implement this as a [`ConnectionModesIteator<Item = ConnectionMode>`]
        let direct = mullvad_types::access_method::Settings::default()
            .access_method_settings
            .get(0)
            .expect("This should always exist")
            .clone();
        Self { mode: direct }
    }
}

impl ConnectionModesIterator for DirectConnectionModeRepeater {
    /// No-op for this [`ConnectionModesIterator`]
    fn set_access_method(&mut self, _: Connection) {}
    /// No-op for this [`ConnectionModesIterator`]
    fn update_access_methods(&mut self, _: Vec<Connection>) {}
    fn peek(&self) -> Connection {
        self.mode.clone()
    }
    fn rotate(&mut self) -> Option<Connection> {
        Some(self.mode.clone())
    }
}
