# What an Unum is, for a cluster folder's Tiltfile: the pillars its kustomization lists, then every app in its apps.yaml.
# An app is pinned to a tag: its YAML at that git tag, and its Docker Hub image at the same tag.

ACCOUNT = 'gaf3'

PILLARS = ['mysql', 'redis']

def pinned(app, tag):
    """The app's own YAML at its tag, with its bare image names made the published images at that tag."""

    yaml = str(local(['kubectl', 'kustomize', 'github.com/unum-apps/%s/kubernetes/base?ref=%s' % (app, tag)], quiet=True))

    lines = []

    for line in yaml.split('\n'):
        if 'image: unum-apps-' in line:
            line = line.replace('image: unum-apps-', 'image: %s/unum-apps-' % ACCOUNT) + ':' + tag
        lines.append(line)

    return '\n'.join(lines)

def unum():
    """Brings up the cluster whose folder holds the Tiltfile that called this."""

    name = os.path.basename(config.main_dir)

    if k8s_context() != 'kind-' + name:
        fail('%s is for kind-%s, not %s: kubectl config use-context kind-%s' % (name, name, k8s_context(), name))

    watch_file(config.main_dir + '/apps.yaml')

    k8s_yaml(kustomize(config.main_dir))

    apps = read_yaml(config.main_dir + '/apps.yaml')

    for app in apps:
        k8s_yaml(config.main_dir + '/../apps/%s/glue.yaml' % app)
        yaml = pinned(app, str(apps[app]['tag']))

        k8s_yaml(blob(yaml))

        # An app's first deploy needs the pillars, so its workloads wait for them.
        for doc in decode_yaml_stream(yaml):
            if doc['kind'] == 'Deployment':
                workload = doc['metadata']['name']
                k8s_resource(workload, resource_deps=PILLARS)
