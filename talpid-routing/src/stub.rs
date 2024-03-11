use crate::imp::RouteManagerCommand;
use futures::{channel::mpsc, StreamExt};
use std::collections::HashSet;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(err_derive::Error, Debug)]
pub enum Error {}

pub struct RouteManager {}

#[derive(Clone)]
pub struct RouteManagerHandle {}

pub struct RouteManagerImpl {}

impl RouteManagerImpl {
    pub async fn new(
        _required_routes: HashSet<crate::RequiredRoute>,
    ) -> crate::imp::imp::Result<Self> {
        Ok(RouteManagerImpl {})
    }

    pub(crate) async fn run(
        self,
        manage_rx: mpsc::UnboundedReceiver<crate::imp::RouteManagerCommand>,
    ) {
        let mut manage_rx = manage_rx.fuse();
        loop {
            match manage_rx.next().await {
                Some(RouteManagerCommand::Shutdown(tx)) => {
                    let _ = tx.send(());
                    return;
                }

                Some(RouteManagerCommand::AddRoutes(_, result_tx)) => {
                    let _ = result_tx.send(Ok(()));
                }
                Some(RouteManagerCommand::ClearRoutes) => {}
                None => {
                    break;
                }
            }
        }
    }
}
