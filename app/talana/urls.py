"""
URL configuration for talana project.
"""
from django.urls import path, include

urlpatterns = [
    path('', include('health.urls')),
]
