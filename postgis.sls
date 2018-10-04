# Install postgresql and postgis
postgis:
  pkg.installed:
     - pkgs: [postgresql-{{ pillar['postgresql']['version'] }}-postgis-{{ pillar['postgresql']['postgis']['version'] }}]
