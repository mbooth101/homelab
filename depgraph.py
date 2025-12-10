#!/usr/bin/env python

import sys
import glob
import graphviz
import os
import yaml

g = graphviz.Digraph(comment='Role Dependency Graph')

role_nodes = {}

def add_node(role):
    if role not in role_nodes:
        role_nodes[role] = g.node(role)
        return True
    return False

def find_deps_of(from_role):
    # Already seen this role
    if not add_node(from_role):
        return
    # This role has no dependencies
    if not os.path.isfile(f'roles/{from_role}/meta/main.yml'):
        return
    with open(f'roles/{from_role}/meta/main.yml', 'r') as f:
        for dep in yaml.safe_load(f)['dependencies']:
            to_role = dep['role']
            g.edge(from_role, to_role)
            find_deps_of(to_role)

def main(argv):
    with open('playbook.yml', 'r') as f:
        for role in yaml.safe_load(f)[0]['roles']:
            find_deps_of(role['role'])
    g.render('depgraph.gv', format='png', outfile='depgraph.png')


if __name__ == "__main__":
    main(sys.argv[1:])
