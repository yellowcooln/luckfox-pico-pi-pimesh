################################################################################
#
# python-mock
#
################################################################################

PYTHON_MOCK_VERSION = 5.2.0
PYTHON_MOCK_SOURCE = mock-$(PYTHON_MOCK_VERSION).tar.gz
PYTHON_MOCK_SITE = https://files.pythonhosted.org/packages/07/8c/14c2ae915e5f9dca5a22edd68b35be94400719ccfa068a03e0fb63d0f6f6
PYTHON_MOCK_SETUP_TYPE = setuptools
PYTHON_MOCK_LICENSE = BSD-3-Clause
PYTHON_MOCK_LICENSE_FILES = LICENSE.txt

$(eval $(python-package))
