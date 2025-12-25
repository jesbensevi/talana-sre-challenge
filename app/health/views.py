import time
import logging
from django.http import JsonResponse
from django.db import connection

logger = logging.getLogger(__name__)


def index(request):
    """Root endpoint with API info."""
    return JsonResponse({
        'service': 'talana-backend',
        'version': '1.0.0',
        'endpoints': {
            '/': 'API info',
            '/health': 'Liveness probe',
            '/ready': 'Readiness probe (database check)',
        }
    })


def healthcheck(request):
    """
    Simple healthcheck endpoint for Kubernetes liveness probe.
    Returns 200 if the application is running.
    """
    return JsonResponse({
        'status': 'healthy',
        'timestamp': time.time(),
    })


def db_check(request):
    """
    Database connectivity check for Kubernetes readiness probe.
    Returns 200 if database connection is successful.
    """
    try:
        start_time = time.time()

        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
            cursor.fetchone()

            # Get PostgreSQL version
            cursor.execute('SELECT version()')
            pg_version = cursor.fetchone()[0]

        latency_ms = (time.time() - start_time) * 1000

        return JsonResponse({
            'status': 'healthy',
            'database': 'connected',
            'latency_ms': round(latency_ms, 2),
            'postgres_version': pg_version.split(',')[0] if pg_version else 'unknown',
            'timestamp': time.time(),
        })

    except Exception as e:
        logger.error(f'Database check failed: {e}')
        return JsonResponse({
            'status': 'unhealthy',
            'database': 'disconnected',
            'error': str(e),
            'timestamp': time.time(),
        }, status=503)
