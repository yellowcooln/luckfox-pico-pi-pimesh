################################################################################
#
# python-cherrypy-cors
#
################################################################################

PYTHON_CHERRYPY_CORS_VERSION = 1.7.0
PYTHON_CHERRYPY_CORS_SOURCE = cherrypy-cors-$(PYTHON_CHERRYPY_CORS_VERSION).tar.gz
PYTHON_CHERRYPY_CORS_SITE = https://files.pythonhosted.org/packages/e0/c3/d62ce781e2e2be9c2d4c5670f0bff518dc1b00396e2ce135dbfdcd4f1b9d
PYTHON_CHERRYPY_CORS_SETUP_TYPE = setuptools
PYTHON_CHERRYPY_CORS_LICENSE = MIT
PYTHON_CHERRYPY_CORS_LICENSE_FILES = LICENSE
PYTHON_CHERRYPY_CORS_DEPENDENCIES = host-python-setuptools-scm python-cherrypy python-httpagentparser
PYTHON_CHERRYPY_CORS_ENV = SETUPTOOLS_SCM_PRETEND_VERSION=$(PYTHON_CHERRYPY_CORS_VERSION)

$(eval $(python-package))
