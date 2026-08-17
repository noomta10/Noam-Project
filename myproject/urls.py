from django.contrib import admin
from django.urls import path
from django.shortcuts import render, redirect
from core.models import Task
from django.views.decorators.csrf import csrf_exempt

@csrf_exempt
def task_list_view(request):
    # Handle new task creation via POST request
    if request.method == 'POST':
        title = request.POST.get('title')
        if title:
            Task.objects.create(title=title)
        return redirect('home')

    # Fetch all tasks from the database (stored in AWS RDS!)
    tasks = Task.objects.all().order_by('-created_at')

    html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="utf-8">
        <title>Noam's DevOps Task Manager</title>
        <style>
            body {{ font-family: Arial, sans-serif; background-color: #f4f4f9; color: #333; max-width: 600px; margin: 50px auto; padding: 20px; background: white; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); }}
            h1 {{ color: #2c3e50; text-align: center; }}
            form {{ display: flex; gap: 10px; margin-bottom: 20px; }}
            input[type="text"] {{ flex: 1; padding: 10px; font-size: 16px; border: 1px solid #ccc; border-radius: 4px; }}
            button {{ padding: 10px 20px; background-color: #3498db; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }}
            button:hover {{ background-color: #2980b9; }}
            ul {{ list-style-type: none; padding: 0; }}
            li {{ background: #ecf0f1; margin-bottom: 8px; padding: 10px; border-radius: 4px; display: flex; justify-content: space-between; align-items: center; }}
            .footer {{ text-align: center; margin-top: 30px; font-size: 12px; color: #7f8c8d; }}
        </style>
    </head>
    <body>
        <h1>Noam's Task Manager 🚀</h1>
        <form method="POST">
            <input type="text" name="title" placeholder="Add a new task..." required>
            <button type="submit">Add Task</button>
        </form>
        <ul>
    """
    
    for task in tasks:
        status = "✔️" if task.completed else "⏳"
        html_content += f"<li><span>{task.title}</span> <span>{status}</span></li>"

    html_content += f"""
        </ul>
        <div class="footer">Powered by AWS (EC2 + RDS) & Docker CI/CD</div>
    </body>
    </html>
    """
    from django.http import HttpResponse
    return HttpResponse(html_content)

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', task_list_view, name='home'),
]