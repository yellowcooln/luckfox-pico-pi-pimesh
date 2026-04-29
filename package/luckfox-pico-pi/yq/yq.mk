################################################################################
#
# yq
#
################################################################################

YQ_VERSION = 4.44.3
YQ_SOURCE = yq_linux_arm.tar.gz
YQ_SITE = https://github.com/mikefarah/yq/releases/download/v$(YQ_VERSION)
YQ_LICENSE = MIT

define YQ_BUILD_CMDS
	true
endef

define YQ_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/yq_linux_arm $(TARGET_DIR)/usr/bin/yq
endef

$(eval $(generic-package))
