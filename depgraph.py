#!/usr/bin/env python

import sys
import glob
import graphviz
import yaml

g = graphviz.Digraph(comment='Role Dependency Graph')

roles = {}

def add_node(role):
    if role not in roles:
        roles[role] = g.node(role)

for path in glob.glob('roles/*/'):
    role = path.split('/')[1]
    add_node(role)

for path in glob.glob('roles/*/meta/main.yml'):
    from_role = path.split('/')[1]
    with open(path, 'r') as f:
        for dep in yaml.safe_load(f)['dependencies']:
            to_role = dep['role']
            add_node(to_role)
            g.edge(from_role, to_role)


g.render('depgraph.gv', format='png', outfile='depgraph.png')
