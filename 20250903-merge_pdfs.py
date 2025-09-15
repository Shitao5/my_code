# 合并一个文件夹中所有的PDF
# 用法：python 20250903-merge_pdfs.py file/ conbine.pdf

import os
import sys
from pypdf import PdfWriter, PdfReader
from natsort import natsorted

def merge_pdfs(pdf_dir, output_path):
    if not os.path.isdir(pdf_dir):
        print(f"❌ 输入目录不存在：{pdf_dir}")
        return

    pdf_files = natsorted([
        f for f in os.listdir(pdf_dir) if f.lower().endswith(".pdf")
    ])

    if not pdf_files:
        print("⚠️ 输入目录中未找到任何 PDF 文件。")
        return

    writer = PdfWriter()

    for pdf in pdf_files:
        full_path = os.path.join(pdf_dir, pdf)
        print(f"✅ 添加：{pdf}")
        reader = PdfReader(full_path)
        for page in reader.pages:
            writer.add_page(page)

    output_dir = os.path.dirname(output_path)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)

    with open(output_path, "wb") as f:
        writer.write(f)

    print(f"\n🎉 合并完成，输出文件为：{os.path.abspath(output_path)}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("用法：python merge_pdfs.py <输入PDF文件夹路径> <输出文件路径>")
        print("示例：python merge_pdfs.py ./pdfs ./output/合并结果.pdf")
    else:
        input_folder = sys.argv[1]
        output_file = sys.argv[2]
        merge_pdfs(input_folder, output_file)
