"""Start the app for real: SQLite on disk, the system clock, port 5000."""
from todo.web import create_production_app

if __name__ == "__main__":
    create_production_app("todos.db").run(debug=True)
