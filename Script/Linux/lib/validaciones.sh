#!/bin/bash
# validaciones.sh - Validaciones de IP, Máscara y Dominio
# Compatible con AlmaLinux 8/9

# ---------- Cargar librería compartida ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# ──────────────────────────────────────────────
# Validar dirección IP
# ──────────────────────────────────────────────
validar_IP() {
    local ip="$1"
    echo -en "${rojo}"

    # Validar formato X.X.X.X solo con números
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "Direccion IP invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos${nc}"
        return 1
    fi

    # Separar octetos
    IFS='.' read -r a b c d <<< "$ip"

    # No puede empezar en 0 ni terminar en 0
    if [[ "$a" -eq 0 || "$d" -eq 0 ]]; then
        echo -e "Direccion IP invalida, no puede ser 0.X.X.X ni X.X.X.0${nc}"
        return 1
    fi

    # Validar ceros a la izquierda y rango 0-255
    for octeto in $a $b $c $d; do
        if [[ "$octeto" =~ ^0[0-9]+ ]]; then
            echo -e "Direccion IP invalida, no se pueden poner 0 a la izquierda a menos que sea 0${nc}"
            return 1
        fi
        if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
            echo -e "Direccion IP invalida, no puede ser mayor a 255 ni menor a 0${nc}"
            return 1
        fi
    done

    # No puede ser 0.0.0.0 ni 255.255.255.255
    if [[ "$ip" == "0.0.0.0" || "$ip" == "255.255.255.255" ]]; then
        echo -e "Direccion IP invalida, no puede ser 0.0.0.0 ni 255.255.255.255${nc}"
        return 1
    fi

    # Loopback reservado (127.x.x.x)
    if [[ "$a" -eq 127 ]]; then
        echo -e "Direccion IP invalida, las direcciones del rango 127.0.0.1 al 127.255.255.255 estan reservadas para host local${nc}"
        return 1
    fi

    # Experimental (240-254.x.x.x)
    if [[ "$a" -ge 240 && "$a" -le 254 ]]; then
        echo -e "Direccion IP invalida, las direcciones del rango 240.0.0.0 al 254.255.255.255 estan reservadas para usos experimentales${nc}"
        return 1
    fi

    # Multicast (224-239.x.x.x)
    if [[ "$a" -ge 224 && "$a" -le 239 ]]; then
        echo -e "Direccion IP invalida, las direcciones del rango 224.0.0.0 al 239.255.255.255 estan reservadas para multicast${nc}"
        return 1
    fi

    echo -en "${nc}"
    return 0
}

# ──────────────────────────────────────────────
# Validar máscara de subred
# ──────────────────────────────────────────────
validar_Mascara() {
    local masc="$1"
    echo -en "${rojo}"

    # Validar formato X.X.X.X solo con números
    if ! [[ "$masc" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "Mascara invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos${nc}"
        return 1
    fi

    IFS='.' read -r a b c d <<< "$masc"

    if [[ "$a" -eq 0 ]]; then
        echo -e "Mascara invalida, no puede ser 0.X.X.X${nc}"
        return 1
    fi

    for octeto in $a $b $c $d; do
        if [[ "$octeto" =~ ^0[0-9]+ ]]; then
            echo -e "Mascara invalida, no se pueden poner 0 a la izquierda a menos que sea 0${nc}"
            return 1
        fi
        if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
            echo -e "Mascara invalida, no puede ser mayor a 255 ni menor a 0${nc}"
            return 1
        fi
    done

    # Validar continuidad de bits
    if [[ "$a" -lt 255 ]]; then
        for octeto in $b $c $d; do
            if [[ "$octeto" -gt 0 ]]; then
                echo -e "Mascara invalida, ocupas acabar los bits del primer octeto (255.X.X.X)${nc}"
                return 1
            fi
        done
    elif [[ "$b" -lt 255 ]]; then
        for octeto in $c $d; do
            if [[ "$octeto" -gt 0 ]]; then
                echo -e "Mascara invalida, ocupas acabar los bits del segundo octeto (255.255.X.X)${nc}"
                return 1
            fi
        done
    elif [[ "$c" -lt 255 ]]; then
        if [[ "$d" -gt 0 ]]; then
            echo -e "Mascara invalida, ocupas acabar los bits del tercer octeto (255.255.255.X)${nc}"
            return 1
        fi
    elif [[ "$d" -gt 252 ]]; then
        echo -e "Mascara invalida, no puede superar 255.255.255.252${nc}"
        return 1
    fi

    echo -en "${nc}"
    return 0
}

# ──────────────────────────────────────────────
# Validar nombre de dominio
# ──────────────────────────────────────────────
validar_Dominio() {
    local domain="$1"
    local domain_regex='^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

    if [[ ! "$domain" =~ $domain_regex ]]; then
        print_warning "Formato de dominio invalido: $domain"
        return 1
    fi

    return 0
}
