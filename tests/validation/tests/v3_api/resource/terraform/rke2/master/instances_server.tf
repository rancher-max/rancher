resource "aws_instance" "master" {
  ami           = "${var.aws_ami}"
  instance_type = "${var.ec2_instance_class}"
  connection {
    type        = "ssh"
    user        = "${var.aws_user}"
    host        = self.public_ip
    private_key = "${file(var.access_key)}"
  }
  subnet_id = var.subnets
  availability_zone = var.availability_zone
  vpc_security_group_ids = ["${var.sg_id}"]
  key_name = "jenkins-rke-validation"
  tags = {
    Name = "${var.resource_name}-rke2server"
  }
  provisioner "remote-exec" {
    inline = [
              "sudo curl -sfL https://raw.githubusercontent.com/rancher/rke2/${var.rke2_version}/install.sh | INSTALL_RKE2_VERSION=${var.rke2_version} INSTALL_RKE2_EXEC=${var.server_flags} sh -",
              "sudo cat /var/lib/rancher/rke2/server/node-token >/tmp/multinode_nodetoken",
              "sudo cat /etc/rancher/rke2/rke2.yaml >/tmp/multinode_kubeconfig",
    ]
  }
  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.access_key} ${var.aws_user}@${aws_instance.master.public_ip}:/tmp/multinode_nodetoken /tmp/"
  } 
  provisioner "local-exec" {
    command = "echo ${aws_instance.master.public_ip} >/tmp/multinode_ip"
  }
  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.access_key} ${var.aws_user}@${aws_instance.master.public_ip}:/tmp/multinode_kubeconfig /tmp/"
  }
}

resource "aws_instance" "master2-ha" {
  ami           = "${var.aws_ami}"
  instance_type = "${var.ec2_instance_class}"
  count         = var.no_of_server_nodes
  connection {
    type        = "ssh"
    user        = "${var.aws_user}"
    host        = self.public_ip
    private_key = "${file(var.access_key)}"
  }
  subnet_id = var.subnets
  availability_zone = var.availability_zone
  vpc_security_group_ids = ["${var.sg_id}"]
  key_name = "jenkins-rke-validation"
  tags = {
    Name = "${var.resource_name}-rke2servers"
  }
  provisioner "remote-exec" {
    inline = [
              "sudo curl -sfL https://raw.githubusercontent.com/rancher/rke2/master/install.sh | INSTALL_RKE2_VERSION=${var.rke2_version} INSTALL_RKE2_EXEC=${var.server_flags} sh -",
    ]
  }
  depends_on       = ["aws_instance.master"]
}

resource "aws_lb_target_group" "aws_tg_9345" {
  port             = 9345
  protocol         = "TCP"
  vpc_id           = "${var.vpc_id}"
  name             = "${var.resource_name}-rke2-tg-92345"
  health_check {
        protocol = "HTTP"
        port = "traffic-port"
        path = "/ping"
        interval = 10
        timeout = 6
        healthy_threshold = 3
        unhealthy_threshold = 3
        matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_80" {
  target_group_arn = "${aws_lb_target_group.aws_tg_80.arn}"
  target_id        = "${aws_instance.master.id}"
  port             = 80
  depends_on       = ["aws_instance.master"]
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_80_2" {
  target_group_arn = "${aws_lb_target_group.aws_tg_80.arn}"
  count            = length(aws_instance.master2-ha)
  target_id        = "${aws_instance.master2-ha[count.index].id}"
  port             = 80
  depends_on       = ["aws_instance.master"]
}


resource "aws_lb_target_group" "aws_tg_6443" {
  port             = 6443
  protocol         = "TCP"
  vpc_id           = "${var.vpc_id}"
  name             = "${var.resource_name}-tg-6443"
  health_check {
        protocol = "TCP"
        port = 80
        path = "/ping"
        interval = 30
        timeout = 10
        healthy_threshold = 3
        unhealthy_threshold = 3
        matcher = "200-399"
  }
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_443" {
  target_group_arn = "${aws_lb_target_group.aws_tg_443.arn}"
  target_id        = "${aws_instance.master.id}"
  port             = 443
  depends_on       = ["aws_instance.master"]
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_443_2" {
  target_group_arn = "${aws_lb_target_group.aws_tg_443.arn}"
  count            = length(aws_instance.master2-ha)
  target_id        = "${aws_instance.master2-ha[count.index].id}"
  port             = 443
  depends_on       = ["aws_instance.master"]
}


resource "aws_lb_target_group" "aws_tg_6443" {
  port             = 6443
  protocol         = "TCP"
  vpc_id           = "${var.vpc_id}"
  name             = "${var.resource_name}-multinode-tg-6443"
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_6443" {
  target_group_arn = "${aws_lb_target_group.aws_tg_6443.arn}"
  target_id        = "${aws_instance.master.id}"
  port             = 6443
  depends_on       = ["aws_instance.master"]
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_6443_2" {
  target_group_arn = "${aws_lb_target_group.aws_tg_6443.arn}"
  count            = length(aws_instance.master2-ha)
  target_id        = "${aws_instance.master2-ha[count.index].id}"
  port             = 6443
  depends_on       = ["aws_instance.master"]
}


resource "aws_lb" "aws_nlb" {
  internal           = false
  load_balancer_type = "network"
  subnets            = ["${var.subnets}"] 
  name               = "${var.resource_name}-multinode-nlb"
}

resource "aws_lb_listener" "aws_nlb_listener_80" {
  load_balancer_arn = "${aws_lb.aws_nlb.arn}"
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.aws_tg_80.arn}"
  }
}

resource "aws_lb_listener" "aws_nlb_listener_443" {
  load_balancer_arn = "${aws_lb.aws_nlb.arn}"
  port              = "443"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.aws_tg_443.arn}"
  }
}

resource "aws_lb_listener" "aws_nlb_listener_6443" {
  load_balancer_arn = "${aws_lb.aws_nlb.arn}"
  port              = "6443"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.aws_tg_6443.arn}"
  }
}

resource "aws_route53_record" "aws_route53" {
  zone_id            = "${data.aws_route53_zone.selected.zone_id}"
  name               = "${var.resource_name}"
  type               = "CNAME"
  ttl                = "300"
  records            = ["${aws_lb.aws_nlb.dns_name}"]
  depends_on         = ["aws_lb_listener.aws_nlb_listener_6443"]
}

data "aws_route53_zone" "selected" {
  name               = "${var.qa_space}"
  private_zone       = false
}

resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "sed s/127.0.0.1/\"${aws_route53_record.aws_route53.fqdn}\"/g /tmp/multinode_kubeconfig>/tmp/multinode_kubeconfig1"
  }
  depends_on = ["aws_instance.master"]
}

resource "null_resource" "store_fqdn" {
  provisioner "local-exec" {
    command = "echo \"${aws_route53_record.aws_route53.fqdn}\" >/tmp/multinode_ip"
  }
  depends_on = ["aws_instance.master"]
}

output "Route53_info" {
  value       = aws_route53_record.aws_route53.*
  description = "List of DNS records"
}

output "hostnames" {
  value       = aws_route53_record.aws_route53.*.fqdn
  description = "List of DNS records"
}

output "public_ip" {
  value = "${aws_instance.master.*.public_ip}"
  description = "The public IP of the AWS node"
}
