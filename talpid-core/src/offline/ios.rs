use futures::channel::mpsc::UnboundedSender;

#[derive(err_derive::Error, Debug)]
#[error(no_from)]
pub enum Error {}

pub struct MonitorHandle {}

impl MonitorHandle {
    pub async fn host_is_offline(&self) -> bool {
        false
    }
}

pub async fn spawn_monitor(notify_tx: UnboundedSender<bool>) -> Result<MonitorHandle, Error> {
    Ok(MonitorHandle {})
}
