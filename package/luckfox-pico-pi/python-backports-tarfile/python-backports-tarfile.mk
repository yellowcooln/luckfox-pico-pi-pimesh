################################################################################
#
# python-backports-tarfile
#
################################################################################

PYTHON_BACKPORTS_TARFILE_VERSION = 1.2.0
PYTHON_BACKPORTS_TARFILE_SOURCE = backports_tarfile-$(PYTHON_BACKPORTS_TARFILE_VERSION).tar.gz
PYTHON_BACKPORTS_TARFILE_SITE = https://files.pythonhosted.org/packages/86/72/cd9b395f25e290e633655a100af28cb253e4393396264a98bd5f5951d50f
PYTHON_BACKPORTS_TARFILE_SETUP_TYPE = setuptools
PYTHON_BACKPORTS_TARFILE_LICENSE = MIT
PYTHON_BACKPORTS_TARFILE_LICENSE_FILES = LICENSE

$(eval $(python-package))
