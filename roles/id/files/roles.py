# An extension for Ipsilon's OIDC identity provider module.
#
# Adds a "roles" scope that releases app-specific role claims such as
# "<app>_role". Claims exist for each "<app>-admins" or "<app>-users" group
# on the system.
#
# Enable it at install time with:
#
#   ipsilon-server-install --openidc-extensions roles

import grp

from ipsilon.providers.openidc.plugins.common import OpenidCExtensionBase


class OpenidCExtension(OpenidCExtensionBase):
    name = 'roles'
    display_name = 'Application roles'
    scopes = {
        'roles': {
            'display_name': 'Your role (admin or user) in applications',
        },
    }

    def get_claims(self, scopes):
        if not self.enabled or 'roles' not in scopes:
            return []
        claims = set()
        for group in grp.getgrall():
            for suffix in ('-admins', '-users'):
                if group.gr_name.endswith(suffix):
                    claims.add(group.gr_name[:-len(suffix)] + '_role')
        return sorted(claims)
