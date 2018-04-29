# Use official PostgreSQL apt repository (PGDG)
{% set version = '10' %}

pgdg_repository:
  pkgrepo.managed:
    - name: deb http://apt.postgresql.org/pub/repos/apt {{ grains['oscodename'] }}-pgdg main {{ version }}
    - file: /etc/apt/sources.list.d/apt.postgresql.org.list
    - key_url: https://www.postgresql.org/media/keys/ACCC4CF8.asc
