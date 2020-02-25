import ast
import os
import pytest

from .test_rke_cluster_provisioning import (create_and_validate_custom_host,
                                            cluster_cleanup)
from .cli_objects import RancherCli
from .common import (ADMIN_TOKEN, USER_TOKEN, CATTLE_TEST_URL, CLUSTER_NAME,
                     AWS_ACCESS_KEY_ID, get_admin_client, get_user_client,
                     get_user_client_and_cluster)

if_test_multicluster = pytest.mark.skipif(
    not AWS_ACCESS_KEY_ID or ast.literal_eval(
        os.environ.get('RANCHER_SKIP_MULTICLUSTER', "False")),
    reason='Multi-Cluster tests are skipped in the interest of time/cost.')


def test_context_switching(rancher_cli: RancherCli):
    rancher_cli.log.info("Testing Context Switching")
    clusters = rancher_cli.get_clusters()
    client = get_user_client()
    projects = client.list_project()
    for project in projects:
        rancher_cli.switch_context(project['id'])
        cluster_name, project_name = rancher_cli.get_context()
        assert any(cluster["id"] == project['clusterId']
                   and cluster["name"] == cluster_name for cluster in clusters)
        assert project_name == project['name']


def test_project_manipulation(remove_cli_resource, rancher_cli: RancherCli):
    rancher_cli.log.info("Testing Creating and Deleting Projects")
    initial_projects = rancher_cli.projects.get_current_projects()
    project = rancher_cli.projects.create_project(use_context=False)
    remove_cli_resource("project", project["id"])
    assert project is not None
    assert len(initial_projects) == len(
        rancher_cli.projects.get_current_projects()) - 1

    rancher_cli.projects.delete_project(project["name"])
    assert len(initial_projects) == len(
        rancher_cli.projects.get_current_projects())


def test_namespace_manipulation(remove_cli_resource, rancher_cli: RancherCli):
    rancher_cli.log.info("Testing Creating, Deleting, and Moving Namespaces")
    p1 = rancher_cli.projects.create_project()
    remove_cli_resource("project", p1["id"])
    namespace = rancher_cli.projects.create_namespace()
    remove_cli_resource("namespace", namespace)
    assert len(rancher_cli.projects.get_namespaces()) == 1
    assert "{}|active".format(
        namespace) in rancher_cli.projects.get_namespaces()

    p2 = rancher_cli.projects.create_project(use_context=False)
    remove_cli_resource("project", p2["id"])
    rancher_cli.projects.move_namespace(namespace, p2["id"])
    assert len(rancher_cli.projects.get_namespaces()) == 0
    rancher_cli.projects.switch_context(p2["id"])
    assert len(rancher_cli.projects.get_namespaces()) == 1
    assert "{}|active".format(
        namespace) in rancher_cli.projects.get_namespaces()

    deleted = rancher_cli.projects.delete_namespace(namespace)
    assert deleted


def test_app_management(remove_cli_resource, rancher_cli: RancherCli):
    rancher_cli.log.info("Testing Install, Upgrade, Rollback, and Delete Apps")
    initial_app = rancher_cli.apps.install("openebs", "openebs",
                                           version="1.5.0", timeout=120)
    assert initial_app["state"] == "active"
    assert initial_app["version"] == "1.5.0"
    remove_cli_resource("apps", initial_app["id"])
    upgraded_app = rancher_cli.apps.upgrade(initial_app, version="1.6.0")
    assert upgraded_app["state"] == "active"
    assert upgraded_app["version"] == "1.6.0"
    rolled_back_app = rancher_cli.apps.rollback(upgraded_app, "1.5.0")
    assert rolled_back_app["state"] == "active"
    assert rolled_back_app["version"] == "1.5.0"
    deleted = rancher_cli.apps.delete(rolled_back_app)
    assert deleted


@if_test_multicluster
def test_multiclusterapp_management(custom_cluster, remove_cli_resource,
                                    admin_cli: RancherCli):
    admin_cli.log.info("Testing Multi-Cluster Apps")

    # Get list of projects to use and ensure that it is 2 or greater
    client = get_admin_client()
    projects = client.list_project()
    targets = []
    for project in projects:
        if project["name"] == "Default":
            admin_cli.switch_context(project['id'])
            cluster_name, project_name = admin_cli.get_context()
            if cluster_name in [custom_cluster.name, CLUSTER_NAME]:
                admin_cli.log.debug("Using cluster: %s", cluster_name)
                targets.append(project["id"])
    assert len(targets) > 1

    # Supplying default answers due to issue with multi-cluster app install:
    # https://github.com/rancher/rancher/issues/25514
    values = {
        "analytics.enabled": "true",
        "defaultImage": "true",
        "defaultPorts": "true",
        "ndm.filters.excludePaths": "loop,fd0,sr0,/dev/ram,/dev/dm-,/dev/md",
        "ndm.filters.excludeVendors": "CLOUDBYT,OpenEBS",
        "ndm.sparse.count": "0",
        "ndm.sparse.enabled": "true",
        "ndm.sparse.path": "/var/openebs/sparse",
        "ndm.sparse.size":"10737418240", "policies.monitoring.enabled": "true"
    }
    initial_app = admin_cli.mcapps.install("openebs", targets=targets,
                                           role="cluster-owner", values=values,
                                           version="1.5.0", timeout=120)
    remove_cli_resource("mcapps", initial_app["name"])
    assert initial_app["state"] == "active"
    assert initial_app["version"] == "1.5.0"
    assert len(initial_app["targets"]) == len(targets)
    upgraded_app = admin_cli.mcapps.upgrade(initial_app, version="1.6.0",
                                            timeout=120)
    assert upgraded_app["state"] == "active"
    assert upgraded_app["version"] == "1.6.0"
    assert upgraded_app["id"] == initial_app["id"]
    rolled_back_app = admin_cli.mcapps.rollback(
        upgraded_app["name"], initial_app["revision"], timeout=120)
    assert rolled_back_app["state"] == "active"
    assert rolled_back_app["version"] == "1.5.0"
    assert rolled_back_app["id"] == upgraded_app["id"]
    deleted = admin_cli.mcapps.delete(rolled_back_app)
    assert deleted


def test_catalog(admin_cli: RancherCli):
    admin_cli.log.info("Testing Creating and Deleting Catalogs")
    admin_cli.login(CATTLE_TEST_URL, ADMIN_TOKEN)
    catalog = admin_cli.catalogs.add("https://git.rancher.io/system-charts",
                                     branch="dev")
    assert catalog is not None
    deleted = admin_cli.catalogs.delete(catalog["name"])
    assert deleted


@pytest.fixture(scope='module')
def custom_cluster(request, rancher_cli):
    rancher_cli.log.info("Creating cluster in AWS to test CLI actions that "
                         "require more than one cluster. Please be patient, "
                         "as this takes some time...")
    node_roles = [["controlplane"], ["etcd"],
                  ["worker"], ["worker"], ["worker"]]
    cluster, aws_nodes = create_and_validate_custom_host(
        node_roles, random_cluster_name=True)

    def fin():
        cluster_cleanup(get_user_client(), cluster, aws_nodes)
    request.addfinalizer(fin)
    return cluster


@pytest.fixture
def admin_cli(request, rancher_cli) -> RancherCli:
    """
       Login occurs at a global scope, so need to ensure we log back in as the
       user in a finalizer so that future tests have no issues.
    """
    rancher_cli.login(CATTLE_TEST_URL, ADMIN_TOKEN)

    def fin():
        rancher_cli.login(CATTLE_TEST_URL, USER_TOKEN)
    request.addfinalizer(fin)
    return rancher_cli


@pytest.fixture(scope='module', autouse="True")
def rancher_cli(request) -> RancherCli:
    client, cluster = get_user_client_and_cluster()
    project_id = client.list_project(name='Default',
                                     clusterId=cluster.id).data[0]["id"]
    cli = RancherCli(CATTLE_TEST_URL, USER_TOKEN, project_id)

    def fin():
        cli.cleanup()
    request.addfinalizer(fin)
    return cli


@pytest.fixture
def remove_cli_resource(request, rancher_cli):
    """Remove a resource after a test finishes even if the test fails.

    How to use:
      pass this function as an argument of your testing function,
      then call this function with the resource type and its id
      as arguments after creating any new resource
    """
    def _cleanup(resource, r_id):
        def clean():
            rancher_cli.switch_context(rancher_cli.DEFAULT_CONTEXT)
            rancher_cli.log.info("Cleaning up {}: {}".format(resource, r_id))
            rancher_cli.run_command("{} delete {}".format(resource, r_id),
                                    expect_error=True)
        request.addfinalizer(clean)
    return _cleanup
