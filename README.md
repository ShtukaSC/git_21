# Топология проекта

- Bastion (Jump) host. Имеет публичный адрес, но доступ из-вне ограничен только 22 портом (SSH). На нем установлен Terraform и Ansible
- 2 ВМ с Nginx
  + Они находятся в приватной сети и не имеют публичного адреса
  + Доступ к ним из-вне по HTTTP(S) осуществляется через Yandex Load Balancer
  + На них установлен Zabbix agent и FileBeat для мониторинга и сбора логов (access и error nginx)
- ВМ Zabbix-сервер. Имеет публичный адрес. Доступ к ним из-вне по HTTTP(S). Дашборды для CPU, RAM, HDD, NET, HTTP:
  + Utilization
  + Satiration
  + Errors
- ВМ Elasticsearch. Не имеет публичного адреса, собирает логи с ВМ с Nginx
- ВМ Kibana. Имеет публичный адрес, соединен с ВМ Elasticsearch. Доступ к ним из-вне по HTTTP(S)
- Бекапы - снепшоты всех ВМ с TTL 1 неделя
План:
![image](https://github.com/user-attachments/assets/11641673-9d71-4ca9-8e2f-b81bdf6275c7)

# Создаем Bastion/Jump host

![image](https://github.com/user-attachments/assets/54db0ada-888b-44a9-8f4a-99feb0ae28b4)


# Настраиваем Bastion/Jump host
(ставим пакеты, terraform..)

# Создаём сервисный аккаунт

![image](https://github.com/user-attachments/assets/59147ba3-0acd-496a-8a6f-b674f04d65a1)

**Устанавливаем провайдера через зеркало**

**Создаём ключ авторизации**

Далее настраиваем провайдера (документация)

Инициалзируем

# Описание инфраструктуры

1. providers.tf - настройка провайдера
2. variables.tf - дефолтные значения
3. terraform.tfvars - переменные, они используются для перезаписи из variables.tf
4. output.tf - вывод
5. main.tf - что будет делать терраформ

**Содержимое файлов находиться в коде**

# Устанавливаем Ansible, создаём каталог для сохранения файлов фнсибла и файлики:

'''
mkdir ~/ansible && cd ~/ansible && touch inventory.yaml && touch playbook.yaml && touch ansible.cfg
'''

**Создаём роли**

**Создаём задачи по установке пакетов**

**Создаем переменную со списком пакетов: nano default_packages/vars/main.yml**
'''
packages_to_install:
  - dnsutils
  - net-tools
  - rsync
  - mc
  - curl
  - wget
  - apt-transport-https
  - gnupg2
  - software-properties-common
  - ca-certificates
  - parted
'''
**Создадим задачи по установке и настройке Nginx**

**Запускаем ансибл**

![image](https://github.com/user-attachments/assets/ea868c17-cd4f-41a9-9ad7-d94ca40acc09)

# Настраиваем сети с помощью Terraform

**Изменяем main.tf**
'''
#Новый ресурс. Создаем новый шлюз для закрытой сети
resource "yandex_vpc_gateway" "private_net" {
  name = "private_net_nat"
  shared_egress_gateway {}
}

#Новый ресурс. Создаем наблицу маршрутизации для наших сетей
resource "yandex_vpc_route_table" "route_with_nat" {
  network_id = "${yandex_vpc_network.network-1.id}" #network-1 - это индекс с которым мы создали сеть в клауде в прошлом уроке

  static_route {
    destination_prefix = "192.168.30.0/24"
    next_hop_address   = "192.168.30.1"
  }

  static_route {
    destination_prefix = "192.168.20.0/24"
    next_hop_address   = "192.168.30.1"
  }

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = "${yandex_vpc_gateway.private_net.id}" #Говорим брать из ресурса, созданного нами выше
  }
}

#Этот ресурс у нас уже есть, добавляем строу
resource "yandex_vpc_subnet" "subnet" {
  for_each       = var.subnets
  name           = each.value["name"]
  zone           = each.value["zone"]
  network_id     = yandex_vpc_network.network-1.id
  v4_cidr_blocks = each.value["v4_cidr_blocks"]
  route_table_id = yandex_vpc_route_table.route_with_nat.id ##Добавляем ее. Связываем подсеть и маршрутизацию, которую мы создали выше
}
'''
# Бастион уже умеет ходить в 30 подсеть, так как имеет интерфейс из этой подсети. Чтобы он мог ходить и на 20, выполняем:
'''
ip route add 192.168.20.0/24 via 192.168.30.1
'''

# Snapshots

**Добавляем в main.tf**
'''
resource "yandex_compute_snapshot" "disk-snap" {
  for_each = var.virtual_machines
  name     = each.value["disk_name"]
  source_disk_id = yandex_compute_disk.boot-disk[each.key].id #Берем ID каждого диска, который мы создаем здесь же в main
}

resource "yandex_compute_snapshot_schedule" "one_week_ttl_every_day" {
  for_each = var.virtual_machines
  name     = each.value["disk_name"]

  schedule_policy {
        expression = "0 0 * * *" #Создаем каждый день в 00:00
  }

  snapshot_count = 7 #У нас живет 7 снепшотов
  retention_period = "168h" #Жизнь каждого по 1 неделе

  disk_ids = ["${yandex_compute_disk.boot-disk[each.key].id}"] #Расписание применяется к ранее созданным дискам
}
'''
# Ansible

Создадим новую роль:

ansible-galaxy init install_agents

install_agents/tasks/main.yml:
'''
# tasks file for install_agents
- name: Installing zabbix_agent2
  block:
    - name: Installing gnupg
      ansible.builtin.apt:
        pkg:
        - gnupg

    - name: Wget and install
      shell: "{{ item }}"
      loop:
        - "wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu24.04_all.deb"
        - "dpkg -i zabbix-release_7.0-2+ubuntu24.04_all.deb > /dev/null"

    - name: Install agent
      ansible.builtin.apt:
        update_cache : true
        pkg:
        - zabbix-agent2

- name: Configuring zabbix-agent
  ansible.builtin.template:
    src: zabbix_agent2.j2
    dest: /etc/zabbix/zabbix_agent2.conf

- name: Restarting and enabling zabbix-agent
  ansible.builtin.service:
    name: zabbix-agent2
    state: restarted
    enabled: yes
'''
install_agents/templates/zabbix_agent2.j2

install_agents/vars/main.yml

**Меняем инвентарник и плейбук**

Подключаемся по ssh к серверу zabbix 

![image](https://github.com/user-attachments/assets/9cb5c643-0cbc-46f1-92fa-5cacde9f8cc3)

![image](https://github.com/user-attachments/assets/4a42a41b-98cd-4e17-a7b5-aaa2d675c915)

![image](https://github.com/user-attachments/assets/1ae1e396-d321-418f-8999-0091f4e8bb6d)

![image](https://github.com/user-attachments/assets/1d828cd6-b789-4349-90ed-5ceeaca1577f)










  









