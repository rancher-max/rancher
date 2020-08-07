from python_terraform import * # NOQA
from .common import *  # NOQA
from .test_import_rke2_cluster import (
    RANCHER_REGION, RANCHER_VPC_ID, RANCHER_SUBNETS, RANCHER_AWS_SG,
    RANCHER_AVAILABILITY_ZONE, RANCHER_AWS_AMI, RANCHER_AWS_USER, HOST_NAME, 
    RANCHER_QA_SPACE, RANCHER_EC2_INSTANCE_CLASS)

RANCHER_RKE2_VERSION = os.environ.get("RANCHER_RKE2_VERSION", "")
RANCHER_NO_OF_SERVER_NODES = \
    os.environ.get("RANCHER_NO_OF_SERVER_NODES", 2)
RANCHER_NO_OF_WORKER_NODES = \
    os.environ.get("RANCHER_NO_OF_WORKER_NODES", 0)
RANCHER_RKE2_SERVER_FLAGS = os.environ.get("RANCHER_RKE2_SERVER_FLAGS", "server")
RANCHER_RKE2_WORKER_FLAGS = os.environ.get("RANCHER_RKE2_WORKER_FLAGS", "agent")
RANCHER_RKE2_KUBECONFIG_PATH = DATA_SUBDIR + "/rke2_kubeconfig.yaml"

def test_create_rke2_single_control_cluster():
    aws_nodes, client, rke2_clusterfilepath = create_single_control_cluster()


def test_create_rke2_multiple_control_cluster():
    rke2_clusterfilepath = create_multiple_control_cluster()


def test_import_rke2_single_control_cluster():
    aws_nodes, client, rke2_clusterfilepath = create_single_control_cluster()
    cluster = create_rancher_cluster(client, rke2_clusterfilepath)
    cluster_cleanup(client, cluster, aws_nodes)


def test_import_rke2_multiple_control_cluster():
    client = get_user_client()
    rke2_clusterfilepath = create_multiple_control_cluster()
    cluster = create_rancher_cluster(client, rke2_clusterfilepath)


def test_delete_rke2():
    delete_resource_in_AWS_by_prefix(RANCHER_HOSTNAME_PREFIX)


def create_single_control_cluster():
    # Get URL and User_Token
    client = get_user_client()
    # Create nodes in AWS
    aws_nodes = create_nodes()

    # Install rke2 on server node
    kubeconfig, node_token = install_rke2_master_node(aws_nodes[0])

    # Join agent nodes -- if there are any
    join_rke2_agent_nodes(aws_nodes[0], aws_nodes[1:], node_token)

    # Update master node IP in kubeconfig file
    kubeconfig = kubeconfig.replace("127.0.0.1", aws_nodes[0].public_ip_address)

    rke2_kubeconfig_file = "rke2_kubeconfig.yaml"
    rke2_clusterfilepath = create_kube_config_file(kubeconfig, rke2_kubeconfig_file)
    print(rke2_clusterfilepath)

    rke2_kubeconfig_file = "rke2_kubeconfig.yaml"
    rke2_clusterfilepath = DATA_SUBDIR + "/" + rke2_kubeconfig_file
    is_file = os.path.isfile(rke2_clusterfilepath)
    assert is_file
    with open(rke2_clusterfilepath, 'r') as f:
        print(f.read())
    return aws_nodes, client, rke2_clusterfilepath


def create_multiple_control_cluster():
    global RANCHER_EXTERNAL_DB_VERSION
    global RANCHER_DB_GROUP_NAME
    rke2_kubeconfig_file = "rke2_kubeconfig.yaml"
    rke2_clusterfilepath = DATA_SUBDIR + "/" + rke2_kubeconfig_file

    tf_dir = DATA_SUBDIR + "/" + "terraform/rke2/master"
    keyPath = os.path.abspath('.') + '/.ssh/' + AWS_SSH_KEY_NAME
    os.chmod(keyPath, 0o400)
    no_of_servers = int(RANCHER_RKE2_NO_OF_SERVER_NODES)
    no_of_servers = no_of_servers - 1

    if RANCHER_EXTERNAL_DB == "MariaDB":
        RANCHER_DB_TYPE = "mysql"
        RANCHER_EXTERNAL_DB_VERSION = "10.3.20" if not RANCHER_EXTERNAL_DB_VERSION else RANCHER_EXTERNAL_DB_VERSION
        RANCHER_DB_GROUP_NAME = "default.mariadb10.3" if not RANCHER_DB_GROUP_NAME else RANCHER_DB_GROUP_NAME
    elif RANCHER_EXTERNAL_DB == "postgres":
        RANCHER_DB_TYPE = "postgres"
        RANCHER_EXTERNAL_DB_VERSION = "11.5" if not RANCHER_EXTERNAL_DB_VERSION else RANCHER_EXTERNAL_DB_VERSION
        RANCHER_DB_GROUP_NAME = "default.postgres11" if not RANCHER_DB_GROUP_NAME else RANCHER_DB_GROUP_NAME
    else:
        RANCHER_DB_TYPE = "mysql"
        RANCHER_EXTERNAL_DB_VERSION = "5.7" if not RANCHER_EXTERNAL_DB_VERSION else RANCHER_EXTERNAL_DB_VERSION
        RANCHER_DB_GROUP_NAME = "default.mysql5.7" if not RANCHER_DB_GROUP_NAME else RANCHER_DB_GROUP_NAME

    tf = Terraform(working_dir=tf_dir,
                   variables={'region': RANCHER_REGION,
                              'vpc_id': RANCHER_VPC_ID,
                              'subnets': RANCHER_SUBNETS,
                              'sg_id': RANCHER_AWS_SG,
                              'availability_zone': RANCHER_AVAILABILITY_ZONE,
                              'aws_ami': RANCHER_AWS_AMI,
                              'aws_user': RANCHER_AWS_USER,
                              'resource_name': RANCHER_HOSTNAME_PREFIX,
                              'access_key': keyPath,
                              'external_db': RANCHER_EXTERNAL_DB,
                              'external_db_version': RANCHER_EXTERNAL_DB_VERSION,
                              'db_group_name': RANCHER_DB_GROUP_NAME,
                              'instance_class': RANCHER_INSTANCE_CLASS,
                              'ec2_instance_class': RANCHER_EC2_INSTANCE_CLASS,
                              'username': RANCHER_DB_USERNAME,
                              'password': RANCHER_DB_PASSWORD,
                              'rke2_version': RANCHER_RKE2_VERSION,
                              'no_of_server_nodes': no_of_servers,
                              'server_flags': RANCHER_RKE2_SERVER_FLAGS,
                              'qa_space': RANCHER_QA_SPACE,
                              'db': RANCHER_DB_TYPE})
    print("Creating cluster")
    tf.init()
    print(tf.plan(out="plan_server.out"))
    print("\n\n")
    print(tf.apply("--auto-approve"))
    print("\n\n")
    if int(RANCHER_RKE2_NO_OF_WORKER_NODES) > 0:
        tf_dir = DATA_SUBDIR + "/" + "terraform/rke2/worker"
        tf = Terraform(working_dir=tf_dir,
                       variables={'region': RANCHER_REGION,
                                  'vpc_id': RANCHER_VPC_ID,
                                  'subnets': RANCHER_SUBNETS,
                                  'sg_id': RANCHER_AWS_SG,
                                  'availability_zone': RANCHER_AVAILABILITY_ZONE,
                                  'aws_ami': RANCHER_AWS_AMI,
                                  'aws_user': RANCHER_AWS_USER,
                                  'ec2_instance_class': RANCHER_EC2_INSTANCE_CLASS,
                                  'resource_name': RANCHER_HOSTNAME_PREFIX,
                                  'access_key': keyPath,
                                  'rke2_version': RANCHER_RKE2_VERSION,
                                  'no_of_worker_nodes': int(RANCHER_NO_OF_WORKER_NODES),
                                  'worker_flags': RANCHER_RKE2_WORKER_FLAGS})

        print("Joining worker nodes")
        tf.init()
        print(tf.plan(out="plan_worker.out"))
        print("\n\n")
        print(tf.apply("--auto-approve"))
        print("\n\n")

    cmd = "cp /tmp/multinode_kubeconfig1 " + rke2_clusterfilepath
    os.system(cmd)
    is_file = os.path.isfile(rke2_clusterfilepath)
    assert is_file
    print(rke2_clusterfilepath)
    with open(rke2_clusterfilepath, 'r') as f:
        print(f.read())
    print("K3s Cluster Created")
    return rke2_clusterfilepath


def create_rancher_cluster(client, rke2_clusterfilepath):
    clustername = random_test_name("testcustom-rke2")
    cluster = client.create_cluster(name=clustername)
    cluster_token = create_custom_host_registration_token(client, cluster)
    command = cluster_token.insecureCommand
    finalimportcommand = command + " --kubeconfig " + rke2_clusterfilepath
    print(finalimportcommand)

    result = run_command(finalimportcommand)

    clusters = client.list_cluster(name=clustername).data
    assert len(clusters) > 0
    print("Cluster is")
    print(clusters[0])

    # Validate the cluster
    cluster = validate_cluster(client, clusters[0],
                               check_intermediate_state=False)

    return cluster


def create_nodes():
    aws_nodes = \
        AmazonWebServices().create_multiple_nodes(
            int(RANCHER_RKE2_NO_OF_WORKER_NODES),
            random_test_name("testcustom-rke2"+"-"+HOST_NAME))
    assert len(aws_nodes) == int(RANCHER_RKE2_NO_OF_WORKER_NODES)
    for aws_node in aws_nodes:
        print("AWS NODE PUBLIC IP {}".format(aws_node.public_ip_address))
    return aws_nodes


def install_rke2_master_node(master):
    # Connect to the node and install rke2 on master
    print("K3s VERSION {}".format(RANCHER_RKE2_VERSION))
    cmd = "curl -sfL https://get.rke2.io | \
     {} sh -s - server --node-external-ip {}".\
        format("INSTALL_RKE2_VERSION={}".format(RANCHER_RKE2_VERSION) if RANCHER_RKE2_VERSION else "", master.public_ip_address)
    print("Master Install {}".format(cmd))
    install_result = master.execute_command(cmd)
    print(install_result)

    # Get node token from master
    cmd = "sudo cat /var/lib/rancher/rke2/server/node-token"
    print(cmd)
    node_token = master.execute_command(cmd)
    print(node_token)

    # Get kube_config from master
    cmd = "sudo cat /etc/rancher/rke2/rke2.yaml"
    kubeconfig = master.execute_command(cmd)
    print(kubeconfig)
    print("NO OF WORKER NODES: {}".format(RANCHER_RKE2_NO_OF_WORKER_NODES))
    print("NODE TOKEN: \n{}".format(node_token))
    print("KUBECONFIG: \n{}".format(kubeconfig))

    return kubeconfig[0].strip("\n"), node_token[0].strip("\n")


def join_rke2_agent_nodes(master, workers, node_token):
    for worker in workers:
        cmd = "curl -sfL https://get.rke2.io | \
             {} RKE2_URL=https://{}:6443 RKE2_TOKEN={} sh -s - ". \
            format("INSTALL_RKE2_VERSION={}".format(RANCHER_RKE2_VERSION) \
                       if RANCHER_RKE2_VERSION else "", master.public_ip_address, node_token)
        cmd = cmd + " {} {}".format("--node-external-ip", worker.public_ip_address)
        print("Joining rke2 master")
        print(cmd)
        install_result = worker.execute_command(cmd)
        print(install_result)


def create_kube_config_file(kubeconfig, rke2_kubeconfig_file):
    rke2_clusterfilepath = DATA_SUBDIR + "/" + rke2_kubeconfig_file
    f = open(rke2_clusterfilepath, "w")
    f.write(kubeconfig)
    f.close()
    return rke2_clusterfilepath
