# Linux kernel append for BeagleBone Black custom configuration
#
# This .bbappend file adds custom configuration to the kernel

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Add kernel configuration fragment
SRC_URI += "file://bbb-custom.cfg"
