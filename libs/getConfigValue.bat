@echo off
call .\libs\vendor\npocmaka\xpath.bat ".\config\config.xml" "//config/add[@key='%1']/@value"
