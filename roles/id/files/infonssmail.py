# An extended nss info plug-in for Ipsilon. Like the built-in nss plug-in,
# but appends an email address to the user info reply based on the user name
# and a configured domain name.
#
# Ipsilon uses only the first enabled info plugin that returns data, so this
# replaces "nss" rather than adding to it. Enable it at install time with:
#
#   ipsilon-server-install --info-nss=no \
#       --info-nssmail yes --info-nssmail-domain <domain>

from ipsilon.info import infonss
from ipsilon.info.common import InfoProviderInstaller
from ipsilon.util.plugin import PluginObject
from ipsilon.util import config as pconfig


class InfoProvider(infonss.InfoProvider):

    def __init__(self, *pargs):
        super().__init__(*pargs)
        self.name = 'nssmail'
        self.description = """
Info plugin that uses the system NSS functions to retrieve user data, and adds
an email address made from the user name and a configured domain."""
        self.new_config(
            self.name,
            pconfig.String('email domain', 'Domain for user email addresses', ''),
        )

    def get_user_attrs(self, user):
        reply = super().get_user_attrs(user)
        domain = self.get_config_value('email domain')
        if reply and domain:
            reply['email'] = '%s@%s' % (user, domain)
        return reply


class Installer(InfoProviderInstaller):

    def __init__(self, *pargs):
        super(Installer, self).__init__()
        self.name = 'nssmail'
        self.pargs = pargs

    def install_args(self, group):
        group.add_argument('--info-nssmail', choices=['yes', 'no'], default='no',
                           help='Use passwd data, plus an email address, to populate user attrs')
        group.add_argument('--info-nssmail-domain', default='',
                           help='Domain to use for user email addresses')

    def configure(self, opts, changes):
        if opts['info_nssmail'] != 'yes':
            return

        # Add configuration data to database
        po = PluginObject(*self.pargs)
        po.name = 'nssmail'
        po.wipe_data()
        po.wipe_config_values()
        po.save_plugin_config({'email domain': opts['info_nssmail_domain']})

        # Update global config to add info plugin
        po.is_enabled = True
        po.save_enabled_state()
