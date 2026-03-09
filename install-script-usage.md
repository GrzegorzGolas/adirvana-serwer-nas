# install-audio-server.sh

Skrypt przygotowuje serwer Debian RT pod:

- Audirvana Studio Core
- SMB / NFS dla biblioteki muzyki
- tuning sysctl pod audio
- tuning Intel NIC przez `ethtool`
- Avahi discovery
- usługę systemd dla Audirvana

## Co robi

1. instaluje pakiety bazowe,
2. ustawia hostname,
3. tworzy użytkownika `audirvana`,
4. zapisuje tuning w `/etc/sysctl.d/99-audio-server.conf`,
5. dopisuje parametry do GRUB,
6. tworzy usługę `audirvanaStudio.service`,
7. konfiguruje SMB i NFS,
8. opcjonalnie ustawia statyczny IP,
9. zapisuje trwały tuning NIC jako usługę systemd.

## Czego nie robi

- nie instaluje samego binarium Audirvana, jeśli nie masz poprawnego źródła/pakietu,
- nie instaluje Diretta Target po stronie renderera,
- nie ustawia BIOS/UEFI,
- nie sprawdza indywidualnych ograniczeń sprzętowych.

## Użycie

```bash
sudo bash scripts/install-audio-server.sh
```

Przed uruchomieniem edytuj sekcję:

- `HOSTNAME_NEW`
- `AUDIRVANA_BIN`
- `NIC_IFACE`
- `SERVER_IP_CIDR`
- `DEFAULT_GW`
- `CONFIGURE_STATIC_IP`

## Po wykonaniu

Zrób reboot i sprawdź:

```bash
uname -r
cat /proc/cmdline
systemctl status audirvanaStudio
ethtool -k eno1
ethtool --show-eee eno1
sysctl net.core.default_qdisc
```
