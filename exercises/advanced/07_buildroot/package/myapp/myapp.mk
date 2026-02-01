################################################################################
#
# myapp - Example custom package for BeagleBone Black
#
################################################################################

MYAPP_VERSION = 1.0.0
MYAPP_SITE = $(BR2_EXTERNAL_BBB_EXTERNAL_PATH)/package/myapp/src
MYAPP_SITE_METHOD = local
MYAPP_LICENSE = MIT
MYAPP_LICENSE_FILES = LICENSE

# Build commands
define MYAPP_BUILD_CMDS
    $(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D)
endef

# Install to target
define MYAPP_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0755 $(@D)/myapp $(TARGET_DIR)/usr/bin/myapp
endef

# Clean commands
define MYAPP_CLEAN_CMDS
    $(MAKE) -C $(@D) clean
endef

$(eval $(generic-package))
