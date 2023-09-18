# Use official PostgreSQL apt repository (PGDG)
{% if grains['osrelease']|float < 22.04  %}
{% set pgdg_repo_name = "deb http://apt.postgresql.org/pub/repos/apt " ~ grains['oscodename'] ~ "-pgdg main " ~ pillar['postgresql']['version'] %}
{% set apt_key = True %}
{% else %}
{% set pgdg_repo_name = "deb [signed-by=/etc/apt/keyrings/pgdg-keyring.gpg] http://apt.postgresql.org/pub/repos/apt "
  ~ grains['oscodename'] ~ "-pgdg main " ~ pillar['postgresql']['version'] %}
{% set apt_key = False %}
{% endif %}

pgdg_repository:
  pkgrepo.managed:
    - name: {{ pgdg_repo_name }}
    - clean_file: True
    - aptkey: {{ apt_key }}
    - file: /etc/apt/sources.list.d/apt.postgresql.org.list
    - key_url: https://www.postgresql.org/media/keys/ACCC4CF8.asc
