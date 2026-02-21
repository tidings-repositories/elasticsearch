FROM docker.elastic.co/elasticsearch/elasticsearch:7.17.29

USER root
RUN /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch analysis-nori

USER elasticsearch