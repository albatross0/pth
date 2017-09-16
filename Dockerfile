FROM centos:7.3.1611
MAINTAINER albatross0@gmail.com

ADD pth-runc.sh /
ADD https://github.com/opencontainers/runc/releases/download/v1.0.0-rc4/runc.amd64 /usr/bin/runc
ADD https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 /usr/bin/jq
RUN chmod +x /usr/bin/runc /usr/bin/jq

# get pause binary
RUN curl -L -s 'https://gcr.io/v2/google_containers/pause-amd64/blobs/sha256:f112334343777b75be77ec1f835e3bbbe7d7bd46e27b6a2ae35c6b3cfea0987c' | tar zxf -

RUN yum install -y iproute traceroute bind-utils iptables conntrack-tools tcpdump strace less file which psmisc wireshark && yum clean all
