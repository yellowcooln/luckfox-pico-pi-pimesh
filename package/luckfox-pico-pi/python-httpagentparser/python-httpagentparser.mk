################################################################################
#
# python-httpagentparser
#
################################################################################

PYTHON_HTTPAGENTPARSER_VERSION = 1.9.9
PYTHON_HTTPAGENTPARSER_SOURCE = httpagentparser-$(PYTHON_HTTPAGENTPARSER_VERSION).tar.gz
PYTHON_HTTPAGENTPARSER_SITE = https://files.pythonhosted.org/packages/f8/44/028b51ff3a2a5c67af2ea929ead36f2d90e9efda1932ff4e45a36aae58eb
PYTHON_HTTPAGENTPARSER_SETUP_TYPE = setuptools
PYTHON_HTTPAGENTPARSER_LICENSE = MIT
PYTHON_HTTPAGENTPARSER_LICENSE_FILES = LICENSE.txt

$(eval $(python-package))
