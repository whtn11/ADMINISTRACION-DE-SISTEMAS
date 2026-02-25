# Colores que me gusta usar :P
rojo='\033[0;31m'
amarillo='\033[1;33m'
verde='\033[0;32m'
azul='\033[1;34m'
cyan='\033[0;36m'
nc='\033[0m'

# Funciones para imprimir mensajes segun que se ocupa
print_warning(){
    echo -e "${rojo}$1${nc}"
}

print_success(){
    echo -e "${verde}$1${nc}"
}

print_info(){
    echo -e "${amarillo}$1${nc}"
}

print_menu(){
    echo -e "${cyan}$1${nc}"
}