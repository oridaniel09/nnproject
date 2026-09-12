import tkinter as tk

# Replace with your actual filename if it is different
filename = "my_render_vectorized.ppm"

root = tk.Tk()
root.title("PPM Viewer")

# tkinter natively supports reading .ppm files
img = tk.PhotoImage(file=filename)
tk.Label(root, image=img).pack()

root.mainloop()