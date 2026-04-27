################################################################################
#
# python-pi-ina219
#
################################################################################

PYTHON_PI_INA219_VERSION = v1.4.1
PYTHON_PI_INA219_SOURCE = $(PYTHON_PI_INA219_VERSION).tar.gz
PYTHON_PI_INA219_SITE = https://github.com/chrisb2/pi_ina219/archive/refs/tags
PYTHON_PI_INA219_SETUP_TYPE = setuptools
PYTHON_PI_INA219_LICENSE = MIT
PYTHON_PI_INA219_DEPENDENCIES = python-adafruit-gpio python-mock

$(eval $(python-package))
