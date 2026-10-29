@echo off
rem Ovinocaprinocultura de corte: recalcula TODOS os meses (sem baixar dados) e copia para o servidor.
cd /d "%~dp0"
python scripts\atualizar_tudo.py --so-resumo --completo
pause
