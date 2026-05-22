# VPNShare

[English](README.md) · **Русский**

Rootless-твик для iOS, который блокирует автоматическое создание правил
Packet Filter (`pf`) демоном Apple для Personal Hotspot / Internet Sharing.
Это позволяет заменить дефолтный iOS-NAT через сотовую сеть (`pdp_ip0`) на
свой собственный — через любой интерфейс, в первую очередь через
VPN-туннель (`utun3`) — и удержать эту настройку,
несмотря на включения/выключения хотспота.

Проверено на RootHide. Должно работать также на Dopamine / palera1n rootless.

Побочное применение: может выступать как частичная замена
[TetherMe](http://www.cobaltapps.com/wp/tetherme-ios-13-update/) на
rootless / RootHide джейлах, где TetherMe недоступен. Так как трафик
хотспота уходит через VPN-туннель, а не напрямую через cellular —
обнаружение тетеринга оператором (TTL/DPI) сильно усложняется. Нюанс:
требуется поднятый VPN (см. [TODO](#todo)).

## Зачем

Цель — раздавать VPN-туннелированный трафик с телефона через точку
доступа. Без SOCKS-прокси на устройстве, без настройки каждого приложения
по отдельности. Просто: включил VPN, включил хотспот, и все подключённые
устройства идут в интернет через VPN.

Препятствие: демон `misd` (`/usr/libexec/misd`) каждый раз при включении
хотспота прописывает свои правила в `pf`, NAT'я трафик клиентов через
сотовую сеть (`pdp_ip0`). Любое заранее установленное вручную правило
маршрутизации через `utun3` затирается этими правилами.

Рабочее правило для раздачи через VPN:
```
echo "nat on utun3 from bridge100:network to any -> (utun3)" | sudo pfctl -f -
```
Эта команда заворачивает клиентов хотспота в VPN-туннель — но как только
misd добавляет свои правила, приоритет получает cellular-NAT, и VPN-маршрут
перестаёт работать.

Самое чистое решение — не дать misd установить эти правила вообще.
Именно этим занимается твик.

## Что misd устанавливает (и что мы вычищаем)

При запуске хотспота misd наполняет PF-anchor
`com.apple.internet-sharing/base_v4` правилами:

```
TRANSLATION RULES:
  nat  on pdp_ip0  inet from 172.20.10.0/28 to any -> (pdp_ip0:0) extfilter ei
  no nat on bridge100 inet from 172.20.10.1 to 172.20.10.0/28
  rdr on bridge100  inet proto tcp from 172.20.10.0/28 to any port = 21 -> 127.0.0.1 port 8021

FILTER RULES:
  scrub on pdp_ip0 all no-df fragment reassemble
  scrub on bridge100 all no-df max-mss 1410 fragment reassemble
  scrub on bridge100 proto esp all no-df fragment reassemble
  pass  on pdp_ip0 all flags any keep state
  pass  on pdp_ip0 proto esp all no state
  pass  on bridge100 all flags any keep state rtable 2
```

Ключевые виновники:
- `nat on pdp_ip0 ...` — гонит трафик клиентов через сотовую сеть
- `pass on bridge100 ... rtable 2` — пинит трафик в отдельную таблицу
  маршрутизации, у которой нет VPN-роута по умолчанию

Если эта пачка не применяется — anchor остаётся пустым, трафик клиентов
проваливается в системную таблицу маршрутизации, и ручное правило
NAT-через-`utun3` начинает работать.

## Как устроено

Фреймворк `PacketFilter` экспортирует небольшой user-space API, которым
misd транзакционно настраивает правила:

- `PFUserBeginRules` — начать транзакцию (`DIOCXBEGIN` ioctl)
- `PFUserAddRule` — добавить правило (`DIOCADDRULE`)
- `PFUserCommitRules` — закоммитить (`DIOCXCOMMIT`)

Твик хукает все три через logos `%hookf` (под капотом — `MSHookFunction`
из ElleKit / Substrate-совместимого слоя) и возвращает «успех» без вызова
оригиналов. В итоге misd считает что всё прописал, а ядро ничего не
видит.

```c
%hookf(int64_t, PFUserBeginRules, int64_t a1)                                  { return 1; }
%hookf(int64_t, PFUserCommitRules, int64_t a1, int64_t a2, int64_t a3, int64_t a4) { return 1; }
%hookf(int64_t, PFUserAddRule, int64_t a1, int64_t a2, xpc_object_t rule)      { return 1; }
```

Почему хукаются именно user-space обёртки, а не ioctl напрямую: проще
адресовать, корректно подписаны для arm64e PAC через `dlsym`, и это
единственная точка входа для нужного anchor'а.

## Ручной способ (без твика)

Тот же эффект можно получить только через `pfctl`, без установки чего-либо —
полезно чтобы попробовать или для отладки:

```
sudo pfctl -F all -a com.apple.internet-sharing
```

Это вычищает вложенные anchor'ы misd. Но есть нюанс: misd **перезаписывает**
свой anchor при каждом переключении хотспота (выкл → вкл переписывает
содержимое). Корневой ruleset он **не трогает** — поэтому твоё вручную
загруженное правило NAT через `utun3` переживает передёргивание — но правила
внутри anchor'а вернутся, и flush придётся делать каждый раз заново. Это
достаточно неудобно, чтобы автоматизировать через твик.

## Использование

1. Установить `.deb` через свой пакетный менеджер (Sileo / Zebra).
2. Поднять VPN. Проверено с [ShadowRocket](https://apps.apple.com/app/shadowrocket/id932747118).
   В принципе должен подойти любой VPN-клиент, поднимающий интерфейс `utunN`,
   но проверен только ShadowRocket. Имя интерфейса смотрится через `ifconfig`.
3. Когда VPN поднят — поставить разовое правило NAT:
   ```
   echo "nat on utun3 from bridge100:network to any -> (utun3)" | sudo pfctl -f -
   ```
4. Включить Personal Hotspot. Клиенты выходят в инет через VPN.

Без поднятого VPN интернета на хотспоте **не будет** — это by design,
потому что мы убрали системный NAT через cellular.

## Сборка

Требования:
- [theos](https://github.com/theos/theos)
- iOS 16.5 SDK в `$THEOS/sdks/` (или любой SDK, в котором ещё лежит
  `PrivateFrameworks/PacketFilter.framework/PacketFilter.tbd` — в SDK
  начиная с Xcode 17+ его вырезали)
- ElleKit, установленный на целевом устройстве

В репе лежит минимальный набор `xpc/*` хедеров под `headers/`, потому что
theos'овый iOS 16.5 SDK неполный (нет директории `xpc/`), а скопированные
из Xcode 26 SDK ссылаются на iOS 17+ типы, которых нет в нашем deployment
target'е. Бандленые хедеры урезаны до нужного минимума.

Собрать и поставить:
```
make package install THEOS_DEVICE_IP=<ip-телефона>
```

Готовый `.deb` остаётся в `packages/`.

## TODO

- **Без поднятого VPN нет интернета на хотспоте.** Так как мы полностью
  убираем системный cellular-NAT, клиенты не имеют выхода в сеть, если в
  данный момент не активен NAT через `utun*`. Нужно сделать корректный
  фолбэк на cellular, когда VPN не запущен.
- **Утечка DNS у подключённых устройств.** Сам телефон корректно гоняет DNS
  через VPN, а клиенты на хотспоте — нет: их DNS-запросы, судя по всему,
  утекают через cellular. Нужен либо `pf`-редирект UDP/53 на `bridge100`
  на доверенный резолвер, либо принудительная подача DNS клиентам через
  DHCP.
- **Сделать включение/выключение через настройки.** Добавить
  PreferenceLoader/Cephei-тогл, чтобы можно было отключить твик в рантайме
  без удаления.

## Структура

```
.
├── Tweak.x          — хуки logos
├── Makefile         — TARGET, зависимости, линковка
├── VPNShare.plist   — Filter = Executables = ("misd")  (инжектится только в misd)
├── control          — метаданные .deb
└── headers/xpc/     — бандленые XPC-хедеры (см. «Сборка»)
```

## Лицензия

Без лицензии — на свой страх и риск. Завязан на поведение приватного
демона; Apple может всё это сломать любым обновлением.
