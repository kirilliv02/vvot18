# Запуск проекта

1. Добавить файл `key.json` в корень проекта
2. Изменить переменные в файле [terraform.tfvars](terraform.tfvars)
3. Выполнить `terraform init`
4. Выполнить `terraform apply` (у сервисного аккаунта должна быть роль `admin`)

# Команды Telegram бота
1. `/getface` - отправляет лицо, которое не определено в бд (чтобы бот добавил имя нужно **ОБЯЗАТЕЛЬНО** "Ответить" на сообщение) 
2. `/find <name>` - отправляет все фотографии, на которых есть человек с этим именем (если на 1 фотографии несколько человек с таким именем, то бот отправит 1 фотографию) 

Мой бот - https://t.me/vvot18_bot

PS Команды и имена **НЕ**чувствительны к регистру  