/// A module for all OpenVPN related process management.
#[cfg(all(not(target_os = "android"), not(target_os = "ios")))]
pub mod openvpn;

/// A trait for stopping subprocesses gracefully.
pub mod stoppable_process;
