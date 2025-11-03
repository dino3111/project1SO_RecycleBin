#!/bin/bash

#################################################
# Script Header Comment
# Autores: Maria Moreira Mané (125102), Claudino José Martins (127368)
# Date: 31.10.2025
# Description: Linux Recycle Bin Simulation (Trabalho Prático 1)
#################################################

# Global Variables
RECYCLE_BIN_DIR="$HOME/.recycle_bin"
FILES_DIR="$RECYCLE_BIN_DIR/files"
METADATA_FILE="$RECYCLE_BIN_DIR/metadata.db"
CONFIG_FILE="$RECYCLE_BIN_DIR/config"
LOG_FILE="$RECYCLE_BIN_DIR/recyclebin.log"

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Auxiliary Functions :

#################################################
# Function: log_operation
# Description: Appends an entry to the recyclebin.log file.
# Parameters: $1 : Log message
# Returns: 0 always
#################################################
log_operation() {
    
    # Cria uma linha de log.
    # Adiciona timestamp e mensagem ao ficheiro de log.
    echo "$(date "+%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

#################################################
# Function: generate_unique_id
# Description: Generates unique ID (timestamp_randomstring) for deleted files.
# Parameters: None
# Returns: Prints unique ID to stdout
#################################################
generate_unique_id() {

    # Obtém timestamp atual em nanossegundos, garantido um id único e cronológico.
    local timestamp=$(date +%s%N)
    
    # Gera uma string aleatória de 6 caracteres (a-z0-9).
    local random=$(LC_CTYPE=C cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)

    # Combinação entre timestamp e random.
    echo "${timestamp}_${random}"
}


# Funções Obrigatórias : 

#################################################
# Function: initialize_recyclebin
# Description: Creates the ~/.recycle_bin/ directory structure.
# Parameters: None
# Returns: 0 on success, 1 on failure
#################################################
initialize_recyclebin() {

    # Verifica se o diretório da lixeira já existe.
    if [ ! -d "$RECYCLE_BIN_DIR" ]; then
        echo -e "${GREEN}Initializing recycle bin structure...${NC}"

        # Cria diretórios principais e arquivos necessários.
        mkdir -p "$FILES_DIR" || { echo -e "${RED}Error: Could not create main directories.${NC}" >&2; return 1; }

        # Cria ficheiros vazios se não existirem.
        echo "ID,ORIGINAL_NAME,ORIGINAL_PATH,DELETION_DATE,FILE_SIZE,FILE_TYPE,PERMISSIONS,OWNER" > "$METADATA_FILE" || { echo -e "${RED}Error: Could not create metadata file.${NC}" >&2; return 1; }
        
        # Configuração padrão:
        echo "MAX_SIZE_MB=1024" > "$CONFIG_FILE"
        echo "RETENTION_DAYS=30" >> "$CONFIG_FILE"

        #  Cria ficheiro de log.
        touch "$LOG_FILE"
        echo -e "${GREEN}Recycle bin initialized successfully in $RECYCLE_BIN_DIR${NC}"
    fi

    # Se já existir, apenas retorna sucesso.
    return 0
}

#################################################
# Function: delete_file
# Description: Moves file(s)/directory(s) to the recycle bin.
# Parameters: $1, $2, ... : Paths to files/directories
# Returns: 0 on success, 1 on failure
#################################################
delete_file() {

    # Verificação de argumentos
    if [ "$#" -eq 0 ]; then
        echo -e "${RED}Error: Please provide one or more files or directories to delete.${NC}" >&2
        return 1
    fi

    # Função auxiliar para verificar quota 
    check_quota
    local success_count=0
    local failure_count=0

    # Processa cada argumento
    for file_path in "$@"; do
        echo "Processing: $file_path"

        # Validação de Segurança:
        # Continue faz que passe para o próximo ficheiro em caso de erro.

        # Verifica existência
        if [ ! -e "$file_path" ]; then
            echo -e "${RED}Error: File or directory '$file_path' does not exist. Skipping.${NC}" >&2
            failure_count=$((failure_count + 1))
            continue
        fi

        # Verifica permissões de leitura e escrita
        if [ ! -r "$file_path" ] || [ ! -w "$file_path" ]; then
             echo -e "${RED}Error: Permission denied for '$file_path'. Must have read/write access. Skipping.${NC}" >&2
             failure_count=$((failure_count + 1))
             continue
        fi

        # Obtem o caminho absoluto
        local absolute_path=$(realpath "$file_path")

        # Previne auto-deleção da lixeira
        if [[ "$absolute_path" == "$RECYCLE_BIN_DIR" || "$absolute_path" == "$FILES_DIR" ]]; then
            echo -e "${RED}Error: Cannot delete the recycle bin itself. Skipping.${NC}" >&2
            failure_count=$((failure_count + 1))
            continue
        fi
        
        # Recolha de Metadados
        local original_name=$(basename "$absolute_path")
        local unique_id=$(generate_unique_id)
        local deletion_date=$(date "+%Y-%m-%d %H:%M:%S")

        # Obtém permissões e proprietário
        local permissions=$(stat -c %a "$absolute_path")
        local owner=$(stat -c %U:%G "$absolute_path")

        # Verifica se é diretório ou ficheiro e obtém tamanho
        local file_type="file"
        [ -d "$absolute_path" ] && file_type="directory"

        # Obtém o tamanho do ficheiro ( 'stat' não funciona em diretórios )
        if [ "$file_type" == "directory" ]; then
            local file_size=$(du -sb "$absolute_path" | awk '{print $1}')
        else
            local file_size=$(stat -c %s "$absolute_path")
        fi

        # Define destino final
        local new_path="$FILES_DIR/$unique_id"

        # Move para a lixeira
        if mv "$absolute_path" "$new_path"; then

            # Regista metadados
            local metadata_line="$unique_id,$original_name,$absolute_path,$deletion_date,$file_size,$file_type,$permissions,$owner"
            echo "$metadata_line" >> "$METADATA_FILE"

            # Regista operação no log e confirmação ao utilizador
            log_operation "DELETE: $original_name (ID: $unique_id) from $absolute_path"
            echo -e "${GREEN}✓ Moved to recycle bin:${NC} $original_name"
            success_count=$((success_count + 1))
        else

            # Se falhar, avisa e incrementa a falha
            echo -e "${RED}Error: Failed to move '$file_path' to recycle bin. Check disk space. Skipping.${NC}" >&2
            failure_count=$((failure_count + 1))
        fi
    done

    # Resumo Final
    echo ""
    echo "Summary: $success_count succeeded, $failure_count failed"
    [ "$failure_count" -eq 0 ] && return 0 || return 1
}

#################################################
# Function: list_recycled
# Description: Displays items currently in the recycle bin.
# Parameters: $1 (Optional): --detailed
# Returns: 0 on success, 1 on error
#################################################
list_recycled() {

    # Verifica se a lixeira está vazia
    # Condição 1: Ficheiro de metadados vazio (apenas cabeçalho)
    # Condição 2: Nenhuma linha além do cabeçalho
    if [ ! -s "$METADATA_FILE" ] || [ "$(tail -n +2 "$METADATA_FILE" | wc -l)" -eq 0 ]; then
        echo "Recycle bin is empty"
        return 0
    fi

    # Modo detalhado (0 normal, 1 detalhado)
    local detailed_mode=0
    [[ "$1" == "--detailed" ]] && detailed_mode=1

    echo -e "${GREEN}=== Recycle Bin Contents ===${NC}"
    if [ "$detailed_mode" -eq 0 ]; then

        # Modo Normal:
        printf "%-25s %-40s %-20s %-10s\n" "ID (Partial)" "Original Filename" "Deletion Date" "Size"
        printf "%s\n" "--------------------------------------------------------------------------------------------------"
        tail -n +2 "$METADATA_FILE" | while IFS=',' read -r ID ORIGINAL_NAME ORIGINAL_PATH DELETION_DATE FILE_SIZE FILE_TYPE PERMISSIONS OWNER; do
            local partial_id="${ID:0:15}..."
            local formatted_size="${FILE_SIZE}B"
            printf "%-25s %-40s %-20s %-10s\n" "$partial_id" "$ORIGINAL_NAME" "$(echo "$DELETION_DATE" | cut -d ' ' -f 1)" "$formatted_size"
        done
    else

        # Modo Detalhado:
        tail -n +2 "$METADATA_FILE" | while IFS=',' read -r ID ORIGINAL_NAME ORIGINAL_PATH DELETION_DATE FILE_SIZE FILE_TYPE PERMISSIONS OWNER; do
            echo ""
            echo "ID: $ID"
            echo "Name: $ORIGINAL_NAME"
            echo "Original Path: $ORIGINAL_PATH"
            echo "Deleted: $DELETION_DATE"
            echo "Size: ${FILE_SIZE} bytes"
            echo "Type: $FILE_TYPE"
            echo "Permissions: $PERMISSIONS"
            echo "Owner: $OWNER"
            printf "%s\n" "--------------------------------------------------"
        done
    fi

    # Número de itens:
    local total_items=$(tail -n +2 "$METADATA_FILE" | wc -l)

    # Tamanho Total para cada linha:
    local total_size_bytes=$(tail -n +2 "$METADATA_FILE" | awk -F',' '{sum+=$5} END {print sum}')
    total_size_bytes=${total_size_bytes:-0}

    # Sumário:
    echo ""
    echo "Total items: $total_items"
    echo "Total storage used: ${total_size_bytes} bytes"
    return 0
}

#################################################
# Function: restore_file
# Description: Restores a file from the recycle bin.
# Parameters: $1 : File ID or original filename/pattern
# Returns: 0 on success, 1 on failure
#################################################
restore_file() {

    # Obtem o ID/Nome
    local search_term="$1"

    # Verficação de Argumento ( se está vazio )
    if [ -z "$search_term" ]; then
        echo -e "${RED}Error: Please provide the File ID or the original filename to restore.${NC}" >&2
        return 1
    fi
    echo -e "${GREEN}Searching for items matching: '${search_term}'...${NC}"

    # Pesquisa de correspondência (ID ou Nome)
    local matched_entry=$(grep -i "$search_term" "$METADATA_FILE" | grep -v 'ORIGINAL_NAME')
    
    # Conta linhas correspondentes
    local num_matches=$(echo "$matched_entry" | grep -c .)

    # Gestão de Resultados da Pesquisa :

    # Nenhuma correspondência
    if [ "$num_matches" -eq 0 ]; then
        echo -e "${RED}Error: No item found matching '${search_term}'.${NC}" >&2
        return 1
    fi
    
    # + 1 Resultado:
    if [ "$num_matches" -gt 1 ]; then
        echo -e "${RED}Warning: Found $num_matches items matching '${search_term}'. Please use the full ID for selective restoration.${NC}" >&2

        # Mostra Resultados:
        echo "$matched_entry" | awk -F',' '{print $1 " | " $2 " | " $4 " | " $6}'
        return 1
    fi

    # Declaração de Variáveis para a única correspondência
    local ID ORIGINAL_NAME ORIGINAL_PATH DELETION_DATE FILE_SIZE FILE_TYPE PERMISSIONS OWNER
    IFS=',' read -r ID ORIGINAL_NAME ORIGINAL_PATH DELETION_DATE FILE_SIZE FILE_TYPE PERMISSIONS OWNER <<< "$matched_entry"
    
    # Confirmação de Restauração ao Utilizador
    echo -e "${GREEN}Preparing to restore:${NC} $ORIGINAL_NAME (ID: $ID)"
    echo "  Destination: $ORIGINAL_PATH"
    read -r -p "Are you sure you want to restore this item? (y/n): " confirmation

    # y ou n
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        echo "Restoration cancelled by user."
        return 0
    fi

    # Gestão do Caminho de Restauração :

    # Extrai o diretório pai
    local parent_dir=$(dirname "$ORIGINAL_PATH")

    # Verifica se o diretório pai existe
    if [ ! -d "$parent_dir" ]; then
        echo "Parent directory does not exist. Creating: $parent_dir"

        # Recria o diretório pai
        mkdir -p "$parent_dir" || { echo -e "${RED}Error: Cannot create parent directory. Permission denied.${NC}" >&2; return 1; }
    fi

    # Define o caminho final de restauração
    local final_restore_path="$ORIGINAL_PATH"

    # Gestão de Conflitos:
    if [ -e "$ORIGINAL_PATH" ]; then
        echo -e "${RED}Conflict:${NC} A file/directory already exists at $ORIGINAL_PATH."
        read -r -p "Overwrite (o) or Restore with new name (n) or Cancel (c)? " conflict_choice
        
        # Decisão do utilizador
        case "$conflict_choice" in
            [Oo]*) 
                echo "Overwriting existing item..."
                rm -rf "$ORIGINAL_PATH" # Remove o existente
                ;;
            [Nn]*)
                local timestamp_suffix="_$(date +%Y%m%d%H%M%S)"

                # Adiciona sufixo de timestamp ao nome
                final_restore_path="${ORIGINAL_PATH}${timestamp_suffix}" 
                echo "Restoring to: $final_restore_path"
                ;;
            *)
                echo "Restoration cancelled due to conflict."
                return 0
                ;;
        esac
    fi

    # Restauro:

    # Define caminho de origem na lixeira
    local source_path="$FILES_DIR/$ID"

    # Tenta mover de volta
    if mv "$source_path" "$final_restore_path"; then
        # Se conseguir, restaura permissões
        chmod "$PERMISSIONS" "$final_restore_path"
        
        # Atualiza metadados (removendo a linha restaurada)
        grep -v "$ID" "$METADATA_FILE" > "$METADATA_FILE.tmp"

        # Substitui o original pelo temporário
        mv "$METADATA_FILE.tmp" "$METADATA_FILE"

        # Log e confirmação
        log_operation "RESTORE: $ORIGINAL_NAME (ID: $ID) restored to $final_restore_path"
        echo -e "${GREEN}Successfully restored:${NC} $ORIGINAL_NAME to $final_restore_path"
        return 0
    else

        # Se falhar, informa o erro
        echo -e "${RED}Error: Failed to move item from recycle bin. Source not found or target permission issue.${NC}" >&2
        return 1
    fi
}

#################################################
# Function: search_recycled
# Description: Searches for items in metadata.db.
# Parameters: $1 : Search pattern
# Returns: 0 if matches found, 1 if no matches or error
#################################################
search_recycled() {

    # Obtem o padrão de pesquisa
    local search_pattern="$1"
    if [ -z "$search_pattern" ]; then

        # Verifica se o padrão está vazio
        echo -e "${RED}Error: Please provide a search pattern (e.g., '*.pdf' or 'report').${NC}" >&2
        return 1
    fi 

    # Preparação padrão pesquisa:

    # Converte '*' em '.*' para regex
    local safe_pattern="${search_pattern//\//\\/}"

    # Escapa caracteres especiais
    local regex_pattern=$(echo "$safe_pattern" | sed 's/\*/.*/g')

    # Execução da pesquisa:

    # Procura no ficheiro de metadados
    local matched_entries
    matched_entries=$(grep -E -i "$regex_pattern" "$METADATA_FILE" | grep -v 'ORIGINAL_NAME' || true)
    
    # Conta correspondências
    local num_matches=$(echo "$matched_entries" | grep -c .)

    # Apresentação de Resultados:

    # Caso se não encontre nada
    if [ "$num_matches" -eq 0 ]; then
        echo "No items found matching the pattern '${search_pattern}'."
        return 0
    fi 

    # Mostra resultados
    echo -e "${GREEN}=== Search Results for: '${search_pattern}' ($num_matches items) ===${NC}"
    printf "%-20s %-30s %-20s %-10s\n" "ID (Partial)" "Original Filename" "Deletion Date" "Size"
    printf "%s\n" "--------------------------------------------------------------------------"

    # Envia cada linha correspondente para formatação
    echo "$matched_entries" | while IFS=',' read -r ID ORIGINAL_NAME ORIGINAL_PATH DELETION_DATE FILE_SIZE FILE_TYPE PERMISSIONS OWNER; do
        
        # Ignora linhas mal formatadas
        if [ -z "$ID" ]; then continue; fi

        # Formata dados para a tabela e imprime
        local partial_id="${ID:0:15}..."
        local date_part=$(echo "$DELETION_DATE" | cut -d ' ' -f 1)
        local formatted_size="${FILE_SIZE}B"
        printf "%-20s %-30s %-20s %-10s\n" "$partial_id" "$ORIGINAL_NAME" "$date_part" "$formatted_size"
    done
    
    return 0
}

#################################################
# Function: empty_recyclebin
# Description: Permanently deletes all or specific items.
# Parameters: $1 (Optional): ID or --force
# Returns: 0 on success, 1 on error
#################################################
empty_recyclebin() {
    local target_id="$1"
    local force_flag=""
    local items_to_delete=""
    local num_deleted=0

    # Verifica se o argumento é --force
    if [[ "$1" == "--force" ]]; then
        force_flag="true"
        target_id=""
    elif [[ "$2" == "--force" ]]; then
        force_flag="true"
        target_id="$1"
    fi

    # Decide o que apagar 
    if [ -z "$target_id" ]; then

        # Se estiver vazio apaga tudo
        local total_items=$(tail -n +2 "$METADATA_FILE" | wc -l)
        if [ "$total_items" -eq 0 ]; then
            echo "Recycle bin is already empty."
            return 0
        fi

        # Se não houver ID, apaga tudo
        items_to_delete=$(tail -n +2 "$METADATA_FILE")
        echo -e "${RED}WARNING: This will permanently delete ALL $total_items items in the recycle bin.${NC}"
    else
        items_to_delete=$(grep -i "$target_id" "$METADATA_FILE" | grep -v 'ORIGINAL_NAME')
        if [ -z "$items_to_delete" ]; then
            echo -e "${RED}Error: No item found matching ID or pattern '${target_id}'.${NC}" >&2
            return 1
        fi
        local item_name=$(echo "$items_to_delete" | head -n 1 | cut -d ',' -f 2)
        echo -e "${RED}WARNING: This will permanently delete item(s) matching '${item_name}' (ID: ${target_id:0:10}...).${NC}"
    fi

    # Confirmação do Utilizador
    if [ -z "$force_flag" ]; then
        local total_to_delete=$(echo "$items_to_delete" | grep -c .)
        read -r -p "Are you sure you want to permanently delete $total_to_delete item(s)? This cannot be undone (y/n): " confirmation
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            echo "Deletion cancelled by user."
            return 0
        fi
    fi

    local TEMP_METADATA="$METADATA_FILE.tmp"
    local items_to_keep=""

    # Loop para apagar ficheiros
    echo "$items_to_delete" | while IFS=',' read -r ID ORIGINAL_NAME ORIGINAL_PATH DELETION_DATE FILE_SIZE FILE_TYPE PERMISSIONS OWNER; do
        if [ -z "$ID" ]; then continue; fi

        # Apaga o ficheiro do sistema
        local item_path="$FILES_DIR/$ID"
        if [ -e "$item_path" ]; then
            rm -rf "$item_path"
            if [ $? -eq 0 ]; then

                # Se conseguir, incrementa contador e log
                num_deleted=$((num_deleted + 1))
                log_operation "EMPTY: Permanently deleted $ORIGINAL_NAME (ID: $ID)."
            else
                items_to_keep+="$ID,"
                # Se falhar, avisa o utilizador e o metadados não será apagado
                echo -e "${RED}Error: Failed to permanently delete $ORIGINAL_NAME. Check system permissions.${NC}" >&2
            fi
        fi
    done
    
    # Atualiza o ficheiro de metadados
    if [ -z "$target_id" ]; then
        # Se estiver vazio, apaga tudo
        head -n 1 "$METADATA_FILE" > "$TEMP_METADATA"
    else
        # Se for empty, recria o ficheiro com cabeçalho
        head -n 1 "$METADATA_FILE" > "$TEMP_METADATA"
        # Adiciona linhas não apagadas
        grep -v "$target_id" "$METADATA_FILE" | grep -v 'ORIGINAL_NAME' >> "$TEMP_METADATA"
    fi

    # Substitui o ficheiro original
    mv "$TEMP_METADATA" "$METADATA_FILE"
    
    # Sumário Final
    echo ""
    echo -e "${GREEN}Operation Complete: $num_deleted item(s) permanently deleted.${NC}"
    return 0
}

#################################################
# Function: display_help
# Description: Prints usage instructions.
# Parameters: None
# Returns: 0 always
#################################################
display_help() {
    # Corrigido: Removido o 'cat << EOF' que causava erro.
    # A função 'echo -e' já processa as cores e escapes como '\t' (tab).
    
    echo -e "${GREEN}=== Linux Recycle Bin Simulation Help ===${NC}"
    echo -e "Usage: $0 <command> [arguments]"
    echo ""
    echo -e "${GREEN}Mandatory Commands:${NC}"
    # O '\t' alinha as descrições numa coluna
    echo -e "  ${GREEN}delete <file(s)>${NC}\t: Moves file(s) or directorie(s) to recycle bin. (Feat 2)"
    echo -e "  ${GREEN}list [--detailed]${NC}\t: Lists contents of the recycle bin. (Feat 3)"
    echo -e "  ${GREEN}restore <ID|name>${NC}\t: Restores file(s) to their original path. (Feat 4)"
    echo -e "  ${GREEN}search <pattern>${NC}\t: Searches for files by name/path pattern. (Feat 5)"
    echo -e "  ${GREEN}empty [ID|--force]${NC}\t: Permanently deletes items. (Feat 6)"
    echo -e "  ${GREEN}help (-h, --help)${NC}\t: Displays this help message. (Feat 7)"
    echo ""
    echo -e "${GREEN}Optional Features (Extra Credit):${NC}"
    # Usar tabs extra para alinhar comandos mais curtos
    echo -e "  ${GREEN}stats${NC}\t\t\t: Shows statistics dashboard. (Feat 8)"
    echo -e "  ${GREEN}cleanup${NC}\t\t\t: Auto-deletes old files based on retention days. (Feat 9)"
    echo -e "  ${GREEN}preview <ID|name>${NC}\t: Previews a file's content inside the bin."
    echo ""
    echo -e "${GREEN}Configuration:${NC}"
    echo -e "  Config File:\t $CONFIG_FILE"
    echo -e "  Metadata File:\t $METADATA_FILE"
    echo ""
    echo -e "${GREEN}Examples:${NC}"
    echo -e "  $0 delete myfile.txt \"my folder\""
    echo -e "  $0 list --detailed"
    echo -e "  $0 restore 17654..."
    
    return 0
}

# Funções Extra Credit

#################################################
# Function: show_statistics
# Description: Displays a dashboard with key statistics.
# Parameters: None
# Returns: 0 on success, 1 on failure
#################################################
show_statistics() {
    # Verificar contagem 
    local total_items=$(tail -n +2 "$METADATA_FILE" | wc -l)

    # Se não houver :
    if [ "$total_items" -eq 0 ]; then
        echo "Recycle bin is empty. No statistics to display."
        return 0
    fi

    # Carregar metadados:
    local data=$(tail -n +2 "$METADATA_FILE")

    # Obter a quota máxima
    local max_quota_mb=$(grep 'MAX_SIZE_MB=' "$CONFIG_FILE" | cut -d '=' -f 2)
    local max_quota_bytes=$((max_quota_mb * 1024 * 1024))

    # Total de bytes usados
    local total_size_bytes=$(echo "$data" | awk -F',' '{sum+=$5} END {print sum}')
    total_size_bytes=${total_size_bytes:-0}

    # Contagem separada de ficheiros / diretórios
    local total_files=$(echo "$data" | grep -c ',file,')
    local total_dirs=$(echo "$data" | grep -c ',directory,')
    
    # Encontra a data mais recente e antiga
    local oldest_entry=$(echo "$data" | sort -t ',' -k 4 -n | head -n 1)
    local newest_entry=$(echo "$data" | sort -t ',' -k 4 -r | head -n 1)
    local oldest_date=$(echo "$oldest_entry" | cut -d ',' -f 4)
    local newest_date=$(echo "$newest_entry" | cut -d ',' -f 4)

    # Calcula o tamanho médio ( divisão por 0 protegida )
    local average_size="N/A"
    if [ "$total_items" -gt 0 ]; then
        average_size=$(echo "$total_size_bytes" "$total_items" | awk '{printf "%d", $1 / $2}')
        average_size="${average_size} bytes"
    fi

    # Calcula % de cota usada
    local quota_percentage=0
    if [ "$max_quota_bytes" -gt 0 ]; then
        quota_percentage=$(echo "$total_size_bytes" "$max_quota_bytes" | awk '{printf "%.1f", ($1/$2)*100}')
    fi

    # Apresentação de Dashboard
    echo -e "${GREEN}=== Recycle Bin Statistics Dashboard ===${NC}"
    printf "%-30s %s\n" "Total Items:" "$total_items"
    printf "%-30s %s\n" "Files:" "$total_files"
    printf "%-30s %s\n" "Directories:" "$total_dirs"
    printf "%s\n" "-------------------------------------------"
    printf "%-30s %s bytes\n" "Total Storage Used:" "$total_size_bytes"
    printf "%-30s %s MB" "Configured Quota:" "$max_quota_mb"
    echo -e " (${RED}${quota_percentage}% Used${NC})"
    printf "%-30s %s\n" "Average File Size:" "$average_size"
    printf "%s\n" "-------------------------------------------"
    printf "%-30s %s\n" "Oldest Item Deletion Date:" "$oldest_date"
    printf "%-30s %s\n" "Newest Item Deletion Date:" "$newest_date"

    return 0
}

#################################################
# Function: auto_cleanup
# Description: Deletes items older than RETENTION_DAYS.
# Parameters: None
# Returns: 0 on success, 1 on failure
#################################################
auto_cleanup() {

    # Obter e VAlidar a retenção
    local retention_days=$(grep 'RETENTION_DAYS=' "$CONFIG_FILE" | cut -d '=' -f 2)

    # Verifica se existe e se é número
    if [ -z "$retention_days" ] || ! [[ "$retention_days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid or missing RETENTION_DAYS value in config file.${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}Starting auto-cleanup. Retention period: $retention_days days.${NC}"

    # Calcula data e hora limite
    local cut_off_date=$(date -d "$retention_days days ago" "+%Y-%m-%d %H:%M:%S")

    # Prepara os ficheiros temporários
    local TEMP_DELETION_LIST="$RECYCLE_BIN_DIR/cleanup_ids.tmp"
    > "$TEMP_DELETION_LIST"  # Guarda os IDs dos ficheiros a apagar
    local TEMP_METADATA="$METADATA_FILE.tmp"
    local num_deleted=0

    # Identifica itens expirados
    # Lê os metadados e compara a data de eliminação 
    tail -n +2 "$METADATA_FILE" | while IFS=',' read -r ID ORIGINAL_NAME ORIGINAL_PATH DELETION_DATE FILE_SIZE FILE_TYPE PERMISSIONS OWNER; do
        if [[ "$DELETION_DATE" < "$cut_off_date" ]]; then
            echo "$ID,$ORIGINAL_NAME" >> "$TEMP_DELETION_LIST"
        fi
    done # se a data for mais antiga à do limite adiciona o id à lista

    # Verifica se há mais ficheiros
    local total_to_clean=$(grep -c . "$TEMP_DELETION_LIST")
    if [ "$total_to_clean" -eq 0 ]; then
        echo "No items found older than $retention_days days."
        rm -f "$TEMP_DELETION_LIST"
        return 0
    fi

    echo -e "Found $total_to_clean items to be permanently deleted."

    # Processa a eliminação
    # Itera sobre a lista de IDs a apagar
    while IFS=',' read -r ID ORIGINAL_NAME; do
        if [ -z "$ID" ]; then continue; fi # ignorar linhas a branco
        local item_path="$FILES_DIR/$ID"
        # Verifica se o ficheiro / diretorio ainda existe
        if [ -e "$item_path" ]; then
            # Remove o f/d físico
            rm -rf "$item_path"
            # bem sucedido ? - atualiza metadados
            if [ $? -eq 0 ]; then
                # reescreve nos metadados
                grep -v "$ID" "$METADATA_FILE" > "$TEMP_METADATA"
                mv "$TEMP_METADATA" "$METADATA_FILE"
                num_deleted=$((num_deleted + 1))
                log_operation "AUTO_CLEANUP: Deleted $ORIGINAL_NAME (ID: $ID) due to retention policy."
            else
                echo -e "${RED}Error: Failed to delete $ORIGINAL_NAME. Check system permissions.${NC}" >&2
            fi
        fi
    done < "$TEMP_DELETION_LIST" # Lê a partir da lista de IDs que criámos

    # Sumário
    echo ""
    echo -e "${GREEN}Auto-Cleanup Complete: $num_deleted item(s) permanently deleted.${NC}"
    rm -f "$TEMP_DELETION_LIST"
    return 0
}

#################################################
# Function: check_quota
# Description: Checks if storage usage exceeds MAX_SIZE_MB.
# Parameters: None
# Returns: 0 if OK, 1 if quota exceeded
#################################################
check_quota() {
    # Obter a quota do ficheiro de configuração e convertê-la para bytes
    local max_quota_mb=$(grep 'MAX_SIZE_MB=' "$CONFIG_FILE" | cut -d '=' -f 2)
    local max_quota_bytes=$((max_quota_mb * 1024 * 1024))

    # Calcula o uso atual
    # Soma a 5ª coluna (size_bytes) do ficheiro de metadados (ignora cabeçalho)
    local total_size_bytes=$(tail -n +2 "$METADATA_FILE" | awk -F',' '{sum+=$5} END {print sum}')
    total_size_bytes=${total_size_bytes:-0}

    # Verificar os limites de utilização
    # Se o uso for 100% ou mais -> 1
    if [ "$total_size_bytes" -ge "$max_quota_bytes" ]; then
        echo -e "${RED}!!! QUOTA EXCEEDED WARNING !!!${NC}"
        echo -e "${RED}The recycle bin storage limit of ${max_quota_mb} MB has been exceeded. Current usage: ${total_size_bytes} bytes.${NC}"
        return 1
    # Aviso se for 90% ou +
    elif [ "$total_size_bytes" -ge $((max_quota_bytes * 90 / 100)) ]; then
        local usage_percent=$(echo "$total_size_bytes" "$max_quota_bytes" | awk '{printf "%d", ($1/$2)*100}')
        echo -e "${YELLOW}WARNING: Recycle bin is ${usage_percent}% full. Consider running cleanup.${NC}"
        return 0
    fi
    # Se estiver abaixo de 90%, está tudo OK.
    return 0
}

#################################################
# Function: preview_file
# Description: Displays preview of a text file or info for a binary file.
# Parameters: $1 : File ID or pattern to preview
# Returns: 0 on success, 1 on failure/not found
#################################################
preview_file() {
    # Argumento
    local search_term="$1"
    
    if [ -z "$search_term" ]; then
        echo -e "${RED}Error: Please provide the File ID or pattern to preview.${NC}" >&2
        return 1
    fi

    # Procura na metadata (ignora cabeçalho)
    local matched_entry=$(grep -i "$search_term" "$METADATA_FILE" | grep -v 'ORIGINAL_NAME')
    local num_matches=$(echo "$matched_entry" | grep -c .)

    # Sem correspondências
    if [ "$num_matches" -eq 0 ]; then
        echo -e "${RED}Error: No item found matching '${search_term}'.${NC}" >&2
        return 1
    fi
    
    # Mais de uma correspondência -> pede especificidade
    if [ "$num_matches" -gt 1 ]; then
        echo -e "${RED}Warning: Found $num_matches items. Please use a more specific ID.${NC}" >&2
        echo "$matched_entry" | awk -F',' '{print $1 " | " $2 " | " $4 " | " $6}'
        return 1
    fi
    
    # Extrai ID da única correspondência
    local ID
    IFS=',' read -r ID _ <<< "$matched_entry" 

    local target_file="$FILES_DIR/$ID" 
    
    # Verifica existência física
    if [ ! -e "$target_file" ]; then
        echo -e "${RED}Error: File with ID '$ID' not found in storage (metadata mismatch).${NC}" >&2
        return 1
    fi
    
    # Determina tipo MIME
    local mime_type=$(file -b --mime-type "$target_file" | cut -d ';' -f 1)
    
    echo -e "${GREEN}=== Preview for ID: $ID (${mime_type}) ===${NC}"

    # Se for texto, mostra primeiras linhas; caso contrário, mostra info do ficheiro
    if [[ "$mime_type" == text/* ]]; then
        echo -e "${GREEN}File Type: TEXT. Showing first 10 lines:${NC}"
        echo "--------------------------------------------------"
        head -n 10 "$target_file"
        echo "--------------------------------------------------"
    else
        echo -e "${GREEN}File Type: BINARY / NON-TEXT. Displaying detailed info:${NC}"
        file "$target_file"
    fi
    
    return 0
}

#################################################
# Function: main
# Description: Main entry point for the script.
# Parameters: None
# Returns: 0 on success, 1 on failure
#################################################
main() {
    if [[ "$1" == "help" || "$1" == "-h" || "$1" == "--help" ]]; then
        display_help
        return 0
    fi
    
    initialize_recyclebin || exit 1

    if [ "$#" -eq 0 ]; then
        echo -e "${RED}Error: No command provided. Use 'help'.${NC}" >&2
        return 1
    fi

    COMMAND="$1"
    shift 

    case "$COMMAND" in
        delete)
            delete_file "$@"
            ;;
        list)
            list_recycled "$@"
            ;;
        restore)
            restore_file "$@"
            ;;
        empty)
            empty_recyclebin "$@"
            ;;
        search)
            search_recycled "$@"
            ;;
        stats)
            show_statistics
            ;;
        cleanup)
            auto_cleanup
            ;;
        preview)
            preview_file "$@"
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$COMMAND'. Use 'help'.${NC}" >&2
            return 1
            ;;
    esac
}

# Ponto de Entrada
main "$@"