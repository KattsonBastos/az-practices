#!/bin/bash

# THIS SCRIPT IF FOR TESTING PURPOSES



# Backup an Azure SQL single database to an Azure storage container

# Variable block
create_env_file(){
    # creates a .env file to store test variables which is going to be used in
    ## the later functions
    rm  -f .env

    let "randomIdentifier=$RANDOM*$RANDOM"

    echo azure_location="East US" >> ./.env
    echo azure_resourceGroup="db-test-$randomIdentifier" >> ./.env
    echo azure_tag="backup-database" >> ./.env
    echo azure_server="azuresql-server-$randomIdentifier" >> ./.env
    echo azure_database="azuresqldb-$randomIdentifier" >> ./.env
    echo azure_login="azureuser" >> ./.env
    echo azure_password="Passw0rD@23" >> ./.env
    echo azure_storage="azuresql$randomIdentifier" >> ./.env
    echo azure_container="azuresql-container-$randomIdentifier" >> ./.env
    now=$(date +"%Y-%m-%d-%H-%M")
    echo azure_bacpac="$now.bacpac" >> ./.env
}

export_envs(){
    # export variables in .env
    if [ -f ".env" ]
    then
        while read p; do
          export "$p"
        done <.env
    fi
}

print_envs(){
    # test if env variables exporting is working
    export_envs

    env | grep azure

    echo "$azure_location"
}

up(){
    # provisioning resources
    export_envs

    echo "Using resource group $azure_resourceGroup with login: $azure_login, password: $azure_password..."

    echo "Creating $azure_resourceGroup in $azure_location..."
    az group create --name $azure_resourceGroup --location "$azure_location" --tags $azure_tag

    echo "Creating azure_storage..."
    az storage account create --name $azure_storage --resource-group $azure_resourceGroup --location "$azure_location" --sku Standard_LRS

    echo "Creating $azure_container on $azure_storage..."
    key=$(az storage account keys list --account-name $azure_storage --resource-group $azure_resourceGroup -o json --query [0].value | tr -d '"')
    az storage container create --name $azure_container --account-key $key --account-name $azure_storage
    
    echo azure_key="$key" >> .env

    echo "Creating $azure_server in $azure_location..."
    az sql server create --name $azure_server --resource-group $azure_resourceGroup --location "$azure_location" --admin-user $azure_login --admin-password $azure_password
    az sql server firewall-rule create --resource-group $azure_resourceGroup --server $azure_server --name AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0

    echo "Creating $azure_database..."
    az sql db create --name $azure_database --resource-group $azure_resourceGroup --server $azure_server --edition Standard 
}

bkp_db(){
    # creating the database backup
    export_envs

    echo "Backing up $azure_database..."
    az sql db export \
        --admin-password $azure_password \
        --admin-user $azure_login \
        --storage-key $azure_key \
        --storage-key-type StorageAccessKey \
        --storage-uri "https://$azure_storage.blob.core.windows.net/$azure_container/$azure_bacpac" \
        --name $azure_database \
        --resource-group $azure_resourceGroup \
        --server $azure_server

    echo "Database $azure_database backup done"
}

restore_db(){
    ## exporting database
    export_envs

    print_envs

    echo "Importing $azure_database..."
    az sql db import \
        --admin-password $azure_password \
        --admin-user $azure_login \
        --storage-key $azure_key \
        --storage-key-type StorageAccessKey \
        --storage-uri "https://$azure_storage.blob.core.windows.net/$azure_container/$azure_bacpac" \
        --name $azure_database \
        --resource-group $azure_resourceGroup \
        --server $azure_server \
        --debug
}

clean(){
    # cleaning resources
    export_envs

    echo "Deleting Resource Group $azure_resourceGroup.."
    az group delete --name $azure_resourceGroup
    echo "Resource Group $azure_resourceGroup deleted!"
}

case $1 in
  up)
    up
    ;;
  bkp_db)
    bkp_db
    ;;
  restore_db)
    restore_db
    ;;
  clean)
    clean
    ;;
  create_env_file)
    create_env_file
    ;;
  print_envs)
    print_envs
    ;;
  *)
    echo "Usage: $0 {up, bkp_db, restore_db, clean, create_env_file, print_envs}"
    ;;
esac