# zapret.sh

Вариант альтернативного скрипта запуска утилиты `nfqws` проекта **zapret** https://github.com/bol-van/zapret

Изначально написан для работы с прошивкой **padavan** (присутствует в репозитории https://gitlab.com/hadzhioglu/padavan-ng ), но потом применение было расширено до <a href="https://openwrt.org/">OpenWRT</a> и дистрибутивов Linux (тестировался на Mint (Ubuntu), Debian, Arch).

Поддерживается работа на основе встроенных в `nfqws` методов autohostlist/hostlist с использованием правил iptables/nftables. `ipset` не применяется.

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

При загрузке компьютера/роутера сервис запустится автоматически. В OpenWRT в `/etc/rc.local` будет прописано обновление списков доменов после полной загрузки роутера.

## Доступные команды:

- старт сервиса: `zapret.sh start`
- остановка сервиса: `zapret.sh stop`
- перезапуск сервиса: `zapret.sh restart`
- перечитать списки сайтов в файлах и обновить правила iptables/nftables: `zapret.sh reload`
- применить правила iptables/nftables: `zapret.sh firewall-start`
- удалить правила iptables/nftables: `zapret.sh firewall-stop`
- скачать файл `nfqws` из репозитория <a href="https://github.com/bol-van/zapret/releases/latest">zapret</a>: `zapret.sh download-nfqws`
- скачать список доменов из репозитория <a href="https://github.com/1andrevich/Re-filter-lists">Re-filter-lists</a>: `zapret.sh download-list`
- скачать и nfqws и список доменов: `zapret.sh download`

## Фильтрация по именам доменов

Поведение аналогично оригинальным скриптам <a href="https://github.com/bol-van/zapret?tab=readme-ov-file#фильтрация-по-именам-доменов">zapret</a>

Файлы списков и их расположение (для прошивки **padavan** пути к файлам вместо `/etc` будут начинаться с `/etc/storage`):
- `/etc/zapret/user.list` - список хостов для фильтрации, формируется пользователем вручную.
- `/etc/zapret/auto.list` - список хостов для фильтрации, формируется во время работы сервиса автоматически. От пользователя требуется в течение одной минуты несколько раз пообновлять страницу сайта, пока он не добавится в список.
- `/etc/zapret/exclude.list` - список хостов, которые являются исключениями и не фильтруются, формируется пользователем вручную.

## Макросы списков для стратегий:

- `<HOSTLIST>` - включены все списки: `user.list`, `auto.list`, `exclude.list`. Работает автодобавление неоткрывающихся сайтов в `auto.list` (необходимо в течение одной минуты несколько раз пообновлять страницу сайта, пока он не добавится в список автоматически)
- `<HOSTLIST_NOAUTO>` - включены списки `user.list`, `exclude.list`, список `auto.list` подключается также как `user.list`. Работает только ручное заполнение списков, автоматического добавления сайтов нет.

## Ленивый режим

Если не хочется возиться с формированием/поиском списков, то можно фильтровать вообще все сайты, за исключением тех, что внесены в `exclude.list`:
- в стратегии использовать макрос `<HOSTLIST_NOAUTO>`
- удалить все записи в списках `user.list` и `auto.list`
- в `exclude.list` добавить хосты, которые не нужно обрабатывать, если сайт из-за фильтрации работает некорректно: например, есть проблемы с сертификатами или отображением данных.

## Стратегии фильтрации

Поведение почти аналогично <a href="https://github.com/bol-van/zapret?tab=readme-ov-file#множественные-стратегии">zapret</a> за исключением того, что стратегии помещаются не в переменные, а записываются в файл `/etc/zapret/strategy` ( **padavan**: `/etc/storage/zapret/strategy` ) для более простого (на мой взгляд) редактирования.

<a href="https://github.com/bol-van/zapret?tab=readme-ov-file#nfqws">Справка по ключам утилиты nfqws для написания стратегий</a>

Для примера:
```
--filter-tcp=80
--dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-fooling=md5sig
<HOSTLIST>

--new
--filter-tcp=443
--dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-fooling=md5sig,badseq
--dpi-desync-fake-tls=/usr/share/zapret/fake/tls_clienthello_www_google_com.bin
<HOSTLIST>

--new
--filter-udp=443
--dpi-desync=fake --dpi-desync-repeats=6
--dpi-desync-fake-quic=/usr/share/zapret/fake/quic_initial_www_google_com.bin
<HOSTLIST_NOAUTO>

--new
--filter-udp=50000-50099
--dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-repeats=6 --dpi-desync-cutoff=n2
```

Строки, начинающиеся с `#`, считаются комментариями и не учитываются. Удобно накидать несколько стратегий для быстрого переключения между ними путём комментирования/раскомментирования нужной.

Подробный разбор:
- `--filter-tcp=80` - фильтровать http трафик
- стратегия фильтрации
- макрос списков хостов
- `--new` - **обязательный** разделитель **между** стратегиями
- `--filter-tcp=443` - фильтровать https трафик
- стратегия фильтрации
- далее указывается <a href="https://github.com/bol-van/zapret?tab=readme-ov-file#реассемблинг">fake-файл</a> из каталога `/usr/share/zapret/fake` для TLS
- макрос списков хостов
- `--new` - **обязательный** разделитель **между** стратегиями
- `--filter-udp=443` - фильтровать quic трафик
- стратегия фильтрации
- далее указывается <a href="https://github.com/bol-van/zapret?tab=readme-ov-file#реассемблинг">fake-файл</a> из каталога `/usr/share/zapret/fake` для QUIC
- макрос списков хостов. Для quic всегда выбирайте `<HOSTLIST_NOAUTO>`
- `--new` - **обязательный** разделитель **между** стратегиями
- `--filter-udp=50000-50099` - фильтрация голосового трафика Discord
- стратегия фильтрации

После внесения изменений в файл стратегий необходимо перезапустить сервис `zapret.sh restart`
