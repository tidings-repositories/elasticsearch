# Elasticsearch 설치 및 구성

## Docker 구성

뜬금없이 Docker를 설치하는 이유는, Elasticsearch가 동작할 서버 인스턴스에서 ELK Stack (Elasticsearch + Logstash + Kibana)를 함께 실행할 예정이라, 서버 리스소 경쟁을 하지 않도록 격리하기 위함입니다.

### 디스크 스왑 공간 할당

우선 Docker에서 공식 문서에 따르면 최소 4GB의 RAM을 사용하길 권장하는데, 현재 그럴 수 있는 상황이 아니라서 가상 메모리 스왑 공간을 4GB로 설정해줬습니다.

```bash
sudo dd if=/dev/zero of=/swapfile bs=128M count=32

sudo chmod 600 /swapfile

sudo mkswap /swapfile

sudo swapon /swapfile

echo /swapfile swap swap defaults 0 0 | sudo tee -a /etc/fstab

echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
```

### Docker 설치

이후 Docker를 설치해줬고,

```bash
sudo yum install -y docker
```

실행과 함께 시스템 리부팅에도 자동 실행될 수 있도록 설정했습니다.

```bash
sudo systemctl start docker

sudo systemctl enable docker
```

그리고 현재 사용하는 Linux 유저를 docker 그룹에 추가하여 루트 권한(sudo)을 이용하지 않아도 docker 명령을 실행할 수 있도록 설정해줬습니다.

```bash
sudo usermod -aG docker ec2-user

newgrp docker
```

### Docker Compose Plugin 설치

Docker를 사용하게된 만큼 Compose를 통해 쉽게 ELK Stack을 구성하고 이식하기 위하여 Compose Plugin을 설치해줬습니다.

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins/

sudo curl -SL https://github.com/docker/compose/releases/download/v2.39.1/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose

sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
```

## Docker Compose로 Elasticsearch, Kibana 구성하기

우선은 로그 수집 및 시각화는 이후에 할 예정이기 때문에 Logstash를 제외한 Elasticsearch 및 Kibana만 Compose로 구성했습니다.

```yaml
#elasticsearch, kibana

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:9.0.4
    environment:
      - discovery.type=single-node
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - xpack.security.enabled=true
    ports:
      - "9200:9200"
    networks:
      - elk
    volumes:
      - es-data:/usr/share/elasticsearch/data

  kibana:
    image: docker.elastic.co/kibana/kibana:9.0.4
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTIC_PASSWORD=${KIBANA_PASSWORD}
    ports:
      - "5601:5601"
    networks:
      - elk
    depends_on:
      - elasticsearch

networks:
  elk:

volumes:
  es-data:
```

이미지로 사용된 건 Docker hub 대신 Elastic에서 직접 [제공](https://www.docker.elastic.co/r/elasticsearch)하는 Docker 이미지 주소가 안정적인 버전일 것으로 생각돼 이를 이용했습니다.

이 때 배포 환경에서 xpack.security를 활성화하는 것이 보안상 좋기 때문에 elasticsearch든, kibana든 접근할 때 비밀번호를 포햄해야 하는데,

compose에 비밀번호를 명시하는 것은 보안적으로 큰 위협이 될 수 있기 때문에 compose 파일과 동일한 위치에 `.env`파일을 만들어 환경 변수로 이용했습니다.

```
# .env
ELASTIC_PASSWORD=[비밀번호]
KIBANA_PASSWORD=[비밀번호]
COMPOSE_PROJECT_NAME=tidings_search
```

이후 실행할 때 프로젝트 이름을 환경 변수로 지정하고, 데몬으로 실행해줬습니다.

```
docker compose up -d
```

## nori 분석 플러그인 설치

```bash
docker exec -it {컨테이너 ID} bash
```

우선 컨테이너에 터미널을 열어서 진입해줬고,

```bash
bin/elasticsearch-plugin install analysis-nori
```

analysis-nori를 설치해줬습니다.

이후 나와서 컨테이너를 재실행해줬습니다.

```bash
exit

docker restart {컨테이너 ID}
```

## Elasticsearch 인덱스 설정

검색용 데이터는 포스트와 유저이고, 기본적으로 인덱싱을 수행하지 않도록 설정에 dynamic 옵션을 false로 설정했습니다.

필요한 필드에 대해서만 명시적으로 mappings에 index: true로 선언해주는 방식으로 하여 성능 개선을 바라고 있습니다.

형태소 분석기의 경우 닉네임은 더 다양하게 분할되지만, 검색은 자연스럽게 되기 위해 analyzer와 search_anlyzer를 구분하여 정의하였습니다.

```json
# post_index.json

{
  "settings": {
    "index": {
      "refresh_interval": "30s"
    },
    "analysis": {
      "tokenizer": {
        "nori_tokenizer": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed"
        }
      },
      "filter": {
        "edge_ngram_filter": {
          "type": "edge_ngram",
          "min_gram": 1,
          "max_gram": 30
        }
      },
      "analyzer": {
        "korean": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["lowercase", "nori_part_of_speech"]
        },
        "edge_ngram_analyzer": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["lowercase", "edge_ngram_filter"]
        }
      }
    }
  },
  "mappings": {
    "dynamic": false,
    "properties": {
      "userId": {
        "type": "text",
        "index": true
      },
      "userName": {
        "type": "text",
        "index": true,
        "analyzer": "edge_ngram_analyzer",
        "search_analyzer": "korean"
      },
      "content": {
        "dynamic": false,
        "type": "object",
        "properties": {
          "text": { "type": "text", "index": true, "analyzer": "korean" },
          "tag": { "type": "keyword", "index": true }
        }
      }
    }
  }
}

```

```json
# member_index.json

{
  "settings": {
    "index": {
      "refresh_interval": "10s"
    },
    "analysis": {
      "tokenizer": {
        "nori_tokenizer": {
          "type": "nori_tokenizer",
          "decompound_mode": "mixed"
        }
      },
      "filter": {
        "edge_ngram_filter": {
          "type": "edge_ngram",
          "min_gram": 1,
          "max_gram": 30
        }
      },
      "analyzer": {
        "korean": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["lowercase", "nori_part_of_speech"]
        },
        "edge_ngram_analyzer": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["lowercase", "edge_ngram_filter"]
        }
      }
    }
  },
  "mappings": {
    "dynamic": false,
    "properties": {
      "public_id": {
        "type": "text",
        "index": true
      },
      "name": {
        "type": "text",
        "index": true,
        "analyzer": "edge_ngram_analyzer",
        "search_analyzer": "korean"
      },
      "bio": {
        "type": "text",
        "index": true,
        "analyzer": "korean"
      }
    }
  }
}
```

위처럼 인덱스 설정을 json으로 만들어줬고, scp로 파일을 Elasticsearch가 실행되는 서버에 보내줬습니다.

```bash
scp post_index.json ec2-user@[ip]:~
scp member_index.json ec2-user@[ip]:~

sudo mv post_index.json /es_index/
sudo mv member_index.json /es_index/
```

굳이 개발 환경에서 REST API로 생성하지 않고, json으로 보낸 이유는 설정을 서버에서 보관하기 위함입니다.

```
curl -u [id]:[pwd] -X PUT "localhost:9200/post-index" \
  -H "Content-Type: application/json" \
  -d @post_index.json

curl -u [id]:[pwd] -X PUT "localhost:9200/member-index" \
  -H "Content-Type: application/json" \
  -d @member_index.json
```
