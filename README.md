# zapret.sh

Вариант альтернативного скрипта запуска утилиты nfqws проекта zapret https://github.com/bol-van/zapret

Изначально писался для работы на прошивке padavan (присутствует в репозитории https://gitlab.com/hadzhioglu/padavan-ng ), но потом применение было расширено до OpwenWRT и дистрибутивов Linux (тестировался на Mint (Ubuntu), Debian, Arch).

Поддерживается работа на основе встроенных в nfqws методов autohostlist/hostlist с использованием правил iptables/nftables. ipset не применяется.

## Установка

Для установки в Linux или OpenWRT скачать репозиторий и запустить от прав администратора: `install.sh`
Для полного удаления запустить от прав администратора: `uninstall.sh`

В современных версиях десктопных дистрибутивов Linux скорее всего нужные пакеты для работы сервиса будут уже установлены. Если нет, то проверьте наличие следующих/похожих пакетов: `curl libnetfilter-conntrack libnetfilter-queue`

Если в вашей версии Linux используется система инициализации отличная от systemd, то организуйте запуск скрипта при старте системы самостоятельно.
Для OpenWRT дополнительна делать ничего не надо, скрипт инсталляции при необходимости установит нужные пакеты.
После установки сервис автоматически запустится.

Запуск сервиса вручную:
- для роутера с OpenWRT: просто перезагрузить либо
  - в веб-интерфейсе: `system -> startup -> zapret -> start`
  - из консоли: `/etc/init.d/zapret start`
- для компьютера с Linux:
  - через службу systemd: `sudo systemctl restart zapret.service`
  - самим скриптом: `sudo zapret.sh restart`

При загрузке компьютера/роутера сервис запустится автоматически. В OpenWRT в rc.local будет прописано обновление списков доменов после полной загрузки роутера.

## Доступные команды:

- старт сервиса: `zapret.sh start`
- остановка сервиса: `zapret.sh stop`
- перезапуск сервиса: `zapret.sh restart`
- перечитать списки сайтов в файлах и обновить правила iptables/nftables: `zapret.sh reload`
- применить правила iptables/nftables: `zapret.sh firewall-start`
- удалить правила iptables/nftables: `zapret.sh firewall-stop`
- попытаться скачать nfqws в `/tmp/nfqws` из репозитория <a href="https://github.com/bol-van/zapret">zapret</a>: `zapret.sh download-nfqws`
- скачать список доменов в `/tmp/filter.list` из репозитория <a href="https://github.com/1andrevich/Re-filter-lists">Re-filter-lists</a>: `zapret.sh download-list`
- скачать и nfqws и список доменов: `zapret.sh download`
