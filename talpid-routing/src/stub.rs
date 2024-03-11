use futures::channel::mpsc;
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
        _manage_rx: mpsc::UnboundedReceiver<crate::imp::RouteManagerCommand>,
    ) {
    }
}
