# zapret.sh

Вариант альтернативного скрипта запуска утилиты `nfqws` проекта <a href="https://github.com/bol-van/zapret">**zapret**</a>

Изначально написан для работы с прошивкой <a href="https://gitlab.com/hadzhioglu/padavan-ng">**padavan-ng**</a>, но потом применение было расширено до <a href="https://openwrt.org/">OpenWRT</a> и дистрибутивов Linux (тестировался на Mint (Ubuntu), Debian, Arch).

Поддерживается работа на основе встроенных в `nfqws` методов autohostlist/hostlist с использованием правил iptables/nftables. `ipset` не применяется.

## Установка

Для **установки** в Linux или <a href="https://openwrt.org/">OpenWRT</a> необходимо скачать и распаковать репозиторий <a href="https://github.com/nilabsent/zapretsh/archive/refs/heads/main.tar.gz">zapretsh</a> любым доступным способом, например:

- для Linux/OpenWRT: `cd /tmp && curl -sL https://github.com/nilabsent/zapretsh/archive/refs/heads/main.tar.gz | tar xz && cd zapretsh-main`
- для OpenWRT в базовой конфигурации: `opkg update && opkg install curl && cd /tmp && curl -sL https://github.com/nilabsent/zapretsh/archive/refs/heads/main.tar.gz | tar xz && cd zapretsh-main`
- для OpenWRT 25 и выше в базовой конфигурации: `apk update && apk add curl && cd /tmp && curl -sL https://github.com/nilabsent/zapretsh/archive/refs/heads/main.tar.gz | tar xz && cd zapretsh-main`

и запустить от прав администратора `./install.sh`

Для полного **удаления** запустить от прав администратора `./uninstall.sh`

В современных версиях десктопных дистрибутивов Linux скорее всего нужные пакеты для работы сервиса будут уже установлены. Если нет, то проверьте наличие следующих/похожих пакетов: `curl libnetfilter-conntrack libnetfilter-queue`

Если в вашей версии Linux используется система инициализации отличная от systemd, то организуйте запуск скрипта при старте системы самостоятельно.
Для OpenWRT дополнительно делать ничего не надо, скрипт инсталляции при необходимости установит нужные пакеты.
После установки сервис автоматически запустится.

Запуск сервиса вручную:
- для роутера с OpenWRT: просто перезагрузить либо
  - в веб-интерфейсе: `system -> startup -> zapret -> start`
  - из консоли: `/etc/init.d/zapret start`
- для компьютера с Linux:
  - через службу systemd: `sudo systemctl restart zapret.service`
  - самим скриптом: `sudo zapret.sh restart`

При загрузке компьютера/роутера сервис запустится автоматически. В OpenWRT в `/etc/rc.local` будет прописано обновление списков доменов после полной загрузки роутера.

## Доступные команды

- `zapret.sh start [strategy_file]` - запуск сервиса; параметром можно указать файл со стратегиями, по умолчанию используется `/etc/zapret/strategy`
- `zapret.sh stop` - остановка сервиса
- `zapret.sh restart [strategy_file]` - перезапуск сервиса; параметром можно указать файл со стратегиями
- `zapret.sh reload` - перечитать списки доменов в файлах и обновить правила iptables/nftables
- `zapret.sh firewall-start` - применить правила iptables/nftables
- `zapret.sh firewall-stop` - удалить правила iptables/nftables
- `zapret.sh download [nfqws_version]` - скачать последнюю версию файла `nfqws` из репозитория <a href="https://github.com/bol-van/zapret/releases/latest">zapret</a> в `/tmp/nfqws`. Если при старте сервиса этот файл присутствует, то он будет запускаться вместо `/usr/bin/nfqws`. Можно указать номер нужной версии `nfqws`, начиная с 69.3
- `zapret.sh download-list` - скачать список доменов из репозитория <a href="https://github.com/1andrevich/Re-filter-lists">Re-filter-lists</a> в `/tmp/filter.list`. При старте сервиса этот список используется совместно с `user.list`

## Фильтрация по именам доменов

Поведение аналогично оригинальным скриптам <a href="https://github.com/bol-van/zapret?tab=readme-ov-file#фильтрация-по-именам-доменов">zapret</a>

Файлы списков и их расположение (для прошивки **padavan** пути к файлам вместо `/etc` будут начинаться с `/etc/storage`):
- `/etc/zapret/user.list` - список доменов для фильтрации, формируется пользователем вручную.
- `/etc/zapret/auto.list` - список доменов для фильтрации, формируется во время работы сервиса автоматически. От пользователя требуется в течение одной минуты несколько раз пообновлять страницу сайта, пока он не добавится в список.
- `/etc/zapret/exclude.list` - список доменов, которые являются исключениями и не фильтруются, формируется пользователем вручную.

## Внешние списки доменов

В файл `/tmp/filter.list` можно скачивать списки доменов по сети командами `curl`, `wget` либо встроенной командой `zapret.sh download-list`. Формат файла: одна строка - один домен. Файл `/tmp/filter.list` находится в оперативной памяти, поэтому скачивать его придётся после каждой загрузки роутера, либо автоматизировать процесс:

- **OpenWRT**: при инсталляции команда `zapret.sh download-list` прописывается в `/etc/rc.local` [ System -> Startup -> Local Startup ], поэтому дополнительно ничего делать не нужно. Если есть желание скачивать собственный список:
  - `curl -sSL "адрес_списка_в_сети" -o /tmp/filter.list`
  - `wget -q "адрес_списка_в_сети" -O /tmp/filter.list`
- **padavan**: в окне [ Персонализация -> Скрипты -> Выполнить после полного запуска маршрутизатора ] добавить в конце строку `sleep 11 && zapret.sh download-list`, либо команды загрузки для `curl`/`wget`, приведённые выше.

После изменений в `/tmp/filter.list` перезагружать сервис не требуется, список задействуется автоматически.

Гнаться за огромными списками на сотни тысяч/миллионы записей на мой взгляд нет никакого смысла: на 99% это мусор, вполне справедливо заблокированный: казино, цп, извращения, наркотики, мошенничества и гигантское количество уже мёртвых зеркал вышеперечисленного непотребства.

## Макросы списков для стратегий

- `<HOSTLIST>` - включены все списки: `user.list`, `auto.list`, `exclude.list`. Работает автодобавление неоткрывающихся сайтов в `auto.list` (необходимо в течение одной минуты несколько раз пообновлять страницу сайта, пока он не добавится в список автоматически)
- `<HOSTLIST_NOAUTO>` - включены списки `user.list`, `exclude.list`, список `auto.list` подключается также как `user.list`. Работает только ручное заполнение списков, автоматического добавления сайтов нет.

## Ленивый режим

Если не хочется возиться с формированием/поиском списков доменов и вы действительно понимаете что делаете, то можно фильтровать вообще все сайты, за исключением тех, что внесены в `exclude.list`:
- в стратегии использовать макрос `<HOSTLIST_NOAUTO>`
- удалить все записи в списках `user.list` и `auto.list`
- не загружать внешние списки по команде `zapret.sh download-list`
- в `exclude.list` добавить домены, которые не нужно обрабатывать, если сайт из-за фильтрации работает некорректно: например, есть проблемы с сертификатами или отображением данных.

Либо просто использовать файл примера таких стратегий для http/https `/etc/zapret/strategy9`, переименовав его в `/etc/zapret/strategy`, там из списков доменов оставлен только `exclude.list`

## Стратегии фильтрации

Поведение почти аналогично <a href="https://github.com/bol-van/zapret?tab=readme-ov-file#множественные-стратегии">zapret</a> за исключением того, что стратегии помещаются не в переменные, а записываются в файл `/etc/zapret/strategy` ( **padavan:** `/etc/storage/zapret/strategy` ) для более простого (на мой взгляд) редактирования.

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
- макрос списков доменов, включено автодобавление заблокированных доменов
- `--new` - **обязательный** разделитель **между** стратегиями
- `--filter-tcp=443` - фильтровать https трафик
- стратегия фильтрации
- указывается <a href="https://github.com/bol-van/zapret?tab=readme-ov-file#реассемблинг">fake-файл</a> из каталога `/usr/share/zapret/fake` для TLS
- макрос списков доменов, включено автодобавление заблокированных доменов
- `--new` - **обязательный** разделитель **между** стратегиями
- `--filter-udp=443` - фильтровать quic трафик
- стратегия фильтрации
- указывается <a href="https://github.com/bol-van/zapret?tab=readme-ov-file#реассемблинг">fake-файл</a> из каталога `/usr/share/zapret/fake` для QUIC
- макрос списков доменов, автодобавление выключено. Для quic всегда выбирайте `<HOSTLIST_NOAUTO>`
- `--new` - **обязательный** разделитель **между** стратегиями
- `--filter-udp=50000-50099` - фильтрация голосового трафика Discord
- стратегия фильтрации

После изменения стратегий необходимо перезапустить сервис: `zapret.sh restart`

## Файл конфигурации

За конфигурацию `zapret.sh` отвечает файл `/etc/zapret/config` ( **padavan:** `/etc/storage/zapret/config` ).

Содержит следующие параметры:
- `ISP_INTERFACE` - интерфейс, трафик на котором будет помечаться для обработки в `nfqws`. По умолчанию значение отсутствует, так как определяется скриптом `zapret.sh` автоматически при старте через маршрут по умолчанию. Можно вручную указать трафик каких интерфейсов обрабатывать, через запятую `eth0,eth2,eth01`
- `NFQUEUE_NUM` - номер очереди в правилах iptables/nftables для `nfqws`. Значение по умолчанию `200`
- `LOG_LEVEL` - логирование работы `nfqws` в `syslog`. Значения: `1` включить, `0` выключить

В конфигурации теперь нет необходимости указывать TCP/UDP порты, сейчас их значения берутся напрямую из стратегий.

После изменения конфигурации необходимо перезапустить сервис: `zapret.sh restart`

## Скрипт, выполняемый после завершения zapret.sh

Файл располагается в `/etc/zapret/post_script.sh` ( padavan: `/etc/storage/zapret/post_script.sh` ), входные параметры, переменные и функции `zapret.sh` доступны и в нём.

Можно размещать собственный функционал, выполняемый, например, после событий `start`/`stop`/`reload`.

## Поддержка flow offloading OpenWRT

Включение/выключение flow offloading поддерживается из системных настроек OpenWRT, дополнительно ничего активировать не нужно: скрипт `zapret.sh` при старте сам определит состояние offloading и внесёт изменения в правила iptables/nftables, чтобы они не мешали работе фильтрации.
При остановке `zapret.sh` системные правила в iptables/nftables восстанавливаются к исходным значениям.

Совместная работа `zapret.sh` с системным flow offloading тестировалось на OpenWRT версий 19, 21 (iptables) и 22, 24 (nftables).
