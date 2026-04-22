################################################################################
#
# python-pycryptodome
#
################################################################################

PYTHON_PYCRYPTODOME_VERSION = 3.23.0
PYTHON_PYCRYPTODOME_SOURCE = pycryptodome-$(PYTHON_PYCRYPTODOME_VERSION).tar.gz
PYTHON_PYCRYPTODOME_SITE = https://files.pythonhosted.org/packages/8e/a6/8452177684d5e906854776276ddd34eca30d1b1e15aa1ee9cefc289a33f5
PYTHON_PYCRYPTODOME_SETUP_TYPE = setuptools
PYTHON_PYCRYPTODOME_LICENSE = BSD-2-Clause, Public-Domain
PYTHON_PYCRYPTODOME_LICENSE_FILES = LICENSE.rst

$(eval $(python-package))
