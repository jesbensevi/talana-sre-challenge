from django.urls import path
from . import views

urlpatterns = [
    path('', views.index, name='index'),
    path('health', views.healthcheck, name='health'),
    path('ready', views.db_check, name='ready'),
]
