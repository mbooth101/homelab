# -*- coding: utf-8 -*-

"""
The ip_ptr filter plugin
"""
from __future__ import absolute_import, division, print_function

__metaclass__ = type

from ansible.errors import AnsibleFilterError
from ansible_collections.ansible.utils.plugins.module_utils.common.argspec_validate import (
    AnsibleArgSpecValidator,
)
from ansible_collections.ansible.utils.plugins.plugin_utils.base.ipaddress_utils import (
    _need_ipaddress,
    ip_address,
)
from ansible_collections.ansible.utils.plugins.plugin_utils.base.ipaddr_utils import (
    ipaddr,
)


try:
    from jinja2.filters import pass_environment
except ImportError:
    from jinja2.filters import environmentfilter as pass_environment


DOCUMENTATION = """
    name: ip_ptr
    options:
        value:
            description:
            - individual IPv4 or IPv6 address input
            type: str
            required: True
"""


RETURN = """
  data:
    type: str
    description:
      - Returns the IP address in reverse DNS PTR record format
"""


@pass_environment
def _ip_ptr(*args, **kwargs):
    """Convert the given IP address to a PTR"""
    keys = ["value"]
    data = dict(zip(keys, args[1:]))
    data.update(kwargs)
    aav = AnsibleArgSpecValidator(data=data, schema=DOCUMENTATION, name="ip_ptr")
    valid, errors, updated_data = aav.validate()
    if not valid:
        raise AnsibleFilterError(errors)
    return ip_ptr(**updated_data)

@_need_ipaddress
def ip_ptr(value):
    try:
        addr4 = ipaddr(value, 'address', version=4)
        addr6 = ipaddr(value, 'address', version=6)
        if addr4:
            prefix = ipaddr(value, 'prefix', version=4)
            return "%s.in-addr.arpa" % '.'.join(reversed(addr4.split('.')[:int(prefix/8)]))
        if addr6:
            prefix = ipaddr(value, 'prefix', version=6)
            prefix_nybbles = int(prefix / 4)
            rev_addr = list(reversed(ip_address(addr6).exploded.replace(':', '')))
            return "%s.ip6.arpa" % '.'.join(rev_addr[int(32 - prefix_nybbles):])
        raise ValueError
    except ValueError:
        msg = "{0} is not a valid IP address".format(value)
        raise AnsibleFilterError(msg)


class FilterModule(object):
    """ip_ptr filter"""

    def filters(self):
        return {"ip_ptr": _ip_ptr}
