use std::ffi::CStr;
use std::os::fd::{AsRawFd, RawFd};

use nix::libc::{c_char, c_ulong, ioctl};
use nix::sys::socket::{getpeername, SockAddr};
use talpid_types::ios::IosContext;

use super::TunConfig;

const UTUN_CTL_NAME: &CStr = c"com.apple.net.utun_control";
const CTLIOCGINFO: c_ulong = 0xc0644e03;

#[repr(C)]
#[allow(clippy::non_camel_case_types)]
struct ctl_info {
    ctl_id: u32,
    ctl_name: [c_char; 96]
}

#[derive(Clone, Copy)]
pub struct VpnServiceTun {
    fd: RawFd,
}

impl AsRawFd for VpnServiceTun {
    fn as_raw_fd(&self) -> RawFd {
        self.fd
    }
}

pub struct Error;

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Tun fd is not found.")
    }
}

pub struct IosTunProvider;

impl IosTunProvider {
    pub fn new(context: IosContext) -> Self {
        IosTunProvider
    }

    pub fn get_tun(&mut self, tun_config: TunConfig) -> Result<VpnServiceTun, Error> {
        let tun_fd = Self::get_tun_fd().ok_or_else(|| Error)?;

        Ok(VpnServiceTun {
            fd: tun_fd
        })
    }

    fn get_tun_fd() -> Option<RawFd> {
        let mut ctl_info: ctl_info = unsafe { std::mem::zeroed() };
        unsafe { 
            std::ptr::copy_nonoverlapping(
                UTUN_CTL_NAME.as_ptr(), 
                ctl_info.ctl_name.as_mut_ptr(), 
                UTUN_CTL_NAME.count_bytes()
            ) 
        };

        (0..1024).find(|fd| {
            let Ok(addr) = getpeername(*fd) else { return false };
            let SockAddr::SysControl(ctl_addr) = addr else { return false };

            let ret = unsafe { ioctl(*fd, CTLIOCGINFO, &mut ctl_info) };
            ret == 0 && ctl_addr.id() == ctl_info.ctl_id
        })
    }
}