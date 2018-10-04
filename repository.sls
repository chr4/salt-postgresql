# Use official PostgreSQL apt repository (PGDG)
pgdg_repository:
  pkgrepo.managed:
    - name: deb http://apt.postgresql.org/pub/repos/apt {{ grains['oscodename'] }}-pgdg main {{ pillar['postgresql']['version'] }}
    - file: /etc/apt/sources.list.d/apt.postgresql.org.list
    - key_url: https://www.postgresql.org/media/keys/ACCC4CF8.asc
