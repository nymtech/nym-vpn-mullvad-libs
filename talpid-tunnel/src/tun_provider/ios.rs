use std::{
    ffi::CStr,
    os::fd::{AsRawFd, BorrowedFd, RawFd},
};

use nix::{
    libc::{self, c_char, c_ulong, sockaddr, sockaddr_ctl, socklen_t, AF_SYSTEM},
    sys::socket,
};
use talpid_types::ios::IosContext;

use super::TunConfig;

const UTUN_CTL_NAME: &CStr = c"com.apple.net.utun_control";
const CTLIOCGINFO: c_ulong = 0xc0644e03;

#[repr(C)]
#[allow(clippy::non_camel_case_types)]
struct ctl_info {
    ctl_id: u32,
    ctl_name: [c_char; 96],
}

pub struct VpnServiceTun {
    tun_fd: RawFd,
    interface_name: String,
}

impl VpnServiceTun {
    pub fn interface_name(&self) -> &str {
        &self.interface_name
    }
}

impl AsRawFd for VpnServiceTun {
    fn as_raw_fd(&self) -> RawFd {
        self.tun_fd
    }
}

#[derive(Debug, err_derive::Error)]
#[error(no_from)]
pub enum Error {
    /// Failure to create a tunnel device.
    #[error(display = "Failed to locate a tunnel device")]
    LocateTunFd,

    /// Failure to obtain device name.
    #[error(display = "Failed to obtain interface name: {}", _0)]
    GetInterfaceName(nix::errno::Errno),

    #[error(display = "Failed to convert interface name to string")]
    ConvertInterfaceNameToString,
}

pub struct IosTunProvider(IosContext);

unsafe impl Send for IosTunProvider {}

impl IosTunProvider {
    pub fn new(context: IosContext) -> Self {
        IosTunProvider(context)
    }

    pub fn get_tun(&mut self, tun_config: TunConfig) -> Result<VpnServiceTun, Error> {
        // todo: apply tun_config
        let tun_fd = Self::get_tun_fd().ok_or(Error::LocateTunFd)?;
        let borrowed_fd = unsafe { BorrowedFd::borrow_raw(tun_fd) };

        let interface_name = socket::getsockopt(&borrowed_fd, socket::sockopt::UtunIfname)
            .map_err(Error::GetInterfaceName)?
            .into_string()
            .map_err(|_| Error::ConvertInterfaceNameToString)?;

        Ok(VpnServiceTun {
            tun_fd,
            interface_name,
        })
    }

    fn get_tun_fd() -> Option<RawFd> {
        let mut ctl_info: ctl_info = unsafe { std::mem::zeroed() };
        unsafe {
            std::ptr::copy_nonoverlapping(
                UTUN_CTL_NAME.as_ptr(),
                ctl_info.ctl_name.as_mut_ptr(),
                UTUN_CTL_NAME.count_bytes(),
            )
        };

        (0..1024).find(|fd| {
            let mut ctl_addr: sockaddr_ctl = unsafe { std::mem::zeroed() };
            let mut len = std::mem::size_of_val(&ctl_addr) as socklen_t;
            let mut ret = unsafe {
                nix::libc::getpeername(
                    *fd,
                    &mut ctl_addr as *mut sockaddr_ctl as *mut sockaddr,
                    &mut len,
                )
            };

            if ret == 0 && ctl_addr.sc_family as i32 == AF_SYSTEM {
                ret = unsafe { libc::ioctl(*fd, CTLIOCGINFO, &mut ctl_info) };
                ret == 0 && ctl_addr.sc_id == ctl_info.ctl_id
            } else {
                false
            }
        })
    }
}
