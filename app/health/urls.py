from django.urls import path
from . import views

urlpatterns = [
    path('', views.index, name='index'),
    path('healthcheck', views.healthcheck, name='healthcheck'),
    path('db-check', views.db_check, name='db_check'),
]
