# What an Unum is, for a cluster folder's Tiltfile: the pillars its kustomization lists, then every app in its apps.yaml.
# An app comes from one of three places:
#   tag:      its YAML at that git tag, its Docker Hub image at the same tag.
#   hash:     its YAML at that commit of main, its Docker Hub image at the hash's first 7 characters.
#   checkout: the repo on disk (a path from here, or absolute), built and run in place by Tilt.
# Whichever, every Service gets an Ingress at <service>.<namespace>.<cluster>.localhost, and a pod resolves that name to
# the cluster's node, where Traefik answers on port 80.

ACCOUNT = 'gaf3'

PILLARS = ['mysql', 'redis']

def get(url):
    return decode_json(str(local(['curl', '-fsS', url], quiet=True)))

def remote(app, ref):
    """The app's own YAML at a git ref, with its bare image names made the published images at the image tag."""

    return str(local(['kubectl', 'kustomize', 'github.com/unum-apps/%s/kubernetes/base?ref=%s' % (app, ref)], quiet=True))

def publish(yaml, tag):
    lines = []

    for line in yaml.split('\n'):
        if 'image: unum-apps-' in line:
            line = line.replace('image: unum-apps-', 'image: %s/unum-apps-' % ACCOUNT) + ':' + tag
        lines.append(line)

    return '\n'.join(lines)

def tagged(app, tag):
    return publish(remote(app, tag), tag)

def hashed(app, short):
    """A commit that is on main: git can only fetch it whole, and Jenkins only pushes images for main."""

    sha = get('https://api.github.com/repos/unum-apps/%s/commits/%s' % (app, short))['sha']
    status = get('https://api.github.com/repos/unum-apps/%s/compare/%s...main' % (app, sha))['status']

    if status not in ['identical', 'ahead']:
        fail('%s %s is not a commit on main; to run other code, use a checkout' % (app, short))

    return publish(remote(app, sha), sha[:7])

def checked_out(app, path):
    """The repo's own dev YAML, its images built from the repo and loaded into the cluster by Tilt."""

    if not os.path.exists(path + '/kubernetes/tilt'):
        fail('%s is not a checkout of %s: %s/kubernetes/tilt is missing' % (path, app, path))

    docs = []

    for doc in decode_yaml_stream(str(kustomize(path + '/kubernetes/tilt'))):
        # The namespace is the Unum's, the same for every source.
        if doc['kind'] != 'Namespace':
            docs.append(doc)

    built = []

    for doc in docs:
        if doc['kind'] != 'Deployment':
            continue

        spec = doc['spec']['template']['spec']

        for container in spec.get('initContainers', []) + spec['containers']:
            image = container['image']
            prefix = 'unum-apps-%s-' % app

            # A migrate init container and the container share an image.
            if image.startswith(prefix) and image not in built:
                built.append(image)
                docker_build(image, path + '/' + image[len(prefix):])

    return str(encode_yaml_stream(docs))

def around(app):
    """What every app needs and its own YAML doesn't carry: its namespace, and the secret that points it at the cluster's MySQL."""

    return str(encode_yaml_stream([
        {'apiVersion': 'v1', 'kind': 'Namespace', 'metadata': {'name': app}},
        {
            'apiVersion': 'v1',
            'kind': 'Secret',
            'metadata': {'name': 'secret', 'namespace': app},
            'stringData': {'mysql.json': '{"host": "mysql.mysql", "user": "root", "password": "root"}'},
        },
    ]))

def ingresses(name, yaml):
    """An Ingress for every Service the app's YAML has, at <service>.<namespace>.<cluster>.localhost: the apps ship none."""

    docs = []

    for doc in decode_yaml_stream(yaml):
        if doc['kind'] == 'Service':
            service = doc['metadata']['name']
            namespace = doc['metadata']['namespace']

            docs.append({
                'apiVersion': 'networking.k8s.io/v1',
                'kind': 'Ingress',
                'metadata': {'name': service, 'namespace': namespace},
                'spec': {'rules': [{
                    'host': '%s.%s.%s.localhost' % (service, namespace, name),
                    'http': {'paths': [{
                        'path': '/',
                        'pathType': 'Prefix',
                        'backend': {'service': {'name': service, 'port': {'number': doc['spec']['ports'][0]['port']}}},
                    }]},
                }]},
            })

    return str(encode_yaml_stream(docs))

def unum():
    """Brings up the cluster whose folder holds the Tiltfile that called this."""

    name = os.path.basename(config.main_dir)

    if k8s_context() != 'kind-' + name:
        fail('%s is for kind-%s, not %s: kubectl config use-context kind-%s' % (name, name, k8s_context(), name))

    watch_file(config.main_dir + '/apps.yaml')

    k8s_yaml(kustomize(config.main_dir))

    # The ingress and the names, once the cluster is up; its CRDs need a server side apply, which Tilt's YAML doesn't do.
    local_resource(
        'ingress', cmd=['scripts/ingress.sh', name], deps=[config.main_dir + '/../' + path for path in ['ingress', 'coredns', 'scripts/ingress.sh']],
        dir=config.main_dir + '/..')

    # The ingress cluster, if there is one, sends this Unum's names here, so a browser uses the names pods do.
    local_resource(
        'route', cmd=['scripts/route.sh', name], deps=[config.main_dir + '/../route', config.main_dir + '/../scripts/route.sh'],
        dir=config.main_dir + '/..')

    apps = read_yaml(config.main_dir + '/apps.yaml')

    for app in apps:
        source = apps[app]

        k8s_yaml(blob(around(app)))

        # What only some apps have, like the NodePorts other Unums and browsers reach them by.
        extra = config.main_dir + '/../apps/%s/extra.yaml' % app

        if os.path.exists(extra):
            k8s_yaml(extra)

        if 'tag' in source:
            yaml = tagged(app, str(source['tag']))
        elif 'hash' in source:
            yaml = hashed(app, str(source['hash']))
        elif 'checkout' in source:
            yaml = checked_out(app, os.path.abspath(config.main_dir + '/../' + str(source['checkout'])))
        else:
            fail('%s in apps.yaml needs a tag, a hash or a checkout' % app)

        k8s_yaml(blob(yaml))
        k8s_yaml(blob(ingresses(name, yaml)))

        # An app's first deploy needs the pillars, so its workloads wait for them.
        for doc in decode_yaml_stream(yaml):
            if doc['kind'] == 'Deployment':
                k8s_resource(doc['metadata']['name'], resource_deps=PILLARS)
