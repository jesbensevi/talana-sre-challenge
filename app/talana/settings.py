"""
Django settings for talana project.
"""
import os
import json
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# Security
SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', 'dev-secret-key-change-in-production')
DEBUG = os.environ.get('DJANGO_DEBUG', 'False').lower() in ('true', '1', 'yes')
ALLOWED_HOSTS = os.environ.get('DJANGO_ALLOWED_HOSTS', '*').split(',')

# Application definition
INSTALLED_APPS = [
    'django.contrib.contenttypes',
    'django.contrib.auth',
    'api',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.middleware.common.CommonMiddleware',
]

ROOT_URLCONF = 'talana.urls'

WSGI_APPLICATION = 'talana.wsgi.application'

# Database configuration from environment or GCP Secret Manager JSON
DB_CONNECTION_JSON = os.environ.get('DB_CONNECTION')

if DB_CONNECTION_JSON:
    try:
        db_config = json.loads(DB_CONNECTION_JSON)
        DATABASES = {
            'default': {
                'ENGINE': 'django.db.backends.postgresql',
                'HOST': db_config.get('host', 'localhost'),
                'PORT': db_config.get('port', '5432'),
                'NAME': db_config.get('database', 'talana_db'),
                'USER': db_config.get('user', 'app_user'),
                'PASSWORD': db_config.get('password', ''),
                'CONN_MAX_AGE': 60,
                'OPTIONS': {
                    'connect_timeout': 10,
                },
            }
        }
    except json.JSONDecodeError:
        DATABASES = {'default': {'ENGINE': 'django.db.backends.sqlite3', 'NAME': ':memory:'}}
else:
    # Fallback: individual environment variables
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'HOST': os.environ.get('DB_HOST', 'localhost'),
            'PORT': os.environ.get('DB_PORT', '5432'),
            'NAME': os.environ.get('DB_NAME', 'talana_db'),
            'USER': os.environ.get('DB_USER', 'app_user'),
            'PASSWORD': os.environ.get('DB_PASSWORD', ''),
            'CONN_MAX_AGE': 60,
            'OPTIONS': {
                'connect_timeout': 10,
            },
        }
    }

# Internationalization
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = False
USE_TZ = True

# Default primary key field type
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# Logging
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'verbose',
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'INFO',
    },
}
