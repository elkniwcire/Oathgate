using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace SteamNite {
    public sealed class ActionButton : Button {
        bool hovered, pressed;
        public bool Primary { get; set; }
        public bool Destructive { get; set; }
        public ActionButton() {
            FlatStyle=FlatStyle.Flat; FlatAppearance.BorderSize=0;
            UseVisualStyleBackColor=false;
            SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);
            Cursor=Cursors.Hand;
        }
        protected override void OnMouseEnter(EventArgs e){hovered=true;Invalidate();base.OnMouseEnter(e);}
        protected override void OnMouseLeave(EventArgs e){hovered=false;pressed=false;Invalidate();base.OnMouseLeave(e);}
        protected override void OnMouseDown(MouseEventArgs e){pressed=true;Invalidate();base.OnMouseDown(e);}
        protected override void OnMouseUp(MouseEventArgs e){pressed=false;Invalidate();base.OnMouseUp(e);}
        protected override void OnEnabledChanged(EventArgs e){Invalidate();base.OnEnabledChanged(e);}
        protected override void OnPaintBackground(PaintEventArgs e){e.Graphics.Clear(Parent==null ? DialogTheme.Background : Parent.BackColor);}
        protected override void OnPaint(PaintEventArgs e){
            var g=e.Graphics;g.Clear(Parent==null ? DialogTheme.Background : Parent.BackColor);g.SmoothingMode=SmoothingMode.AntiAlias;
            using(var path=DialogTheme.Round(new RectangleF(1,1,Width-2,Height-2),8)) {
                Color fill=!Enabled ? DialogTheme.Panel : Primary ? DialogTheme.Accent : hovered ? DialogTheme.Hover : DialogTheme.Input;
                if(pressed && Enabled) fill=Primary ? Color.FromArgb(143,168,215) : DialogTheme.Selection;
                using(var brush=new SolidBrush(fill))g.FillPath(brush,path);
                using(var pen=new Pen(Focused ? DialogTheme.Accent : Primary ? fill : DialogTheme.Border))g.DrawPath(pen,path);
            }
            var color=!Enabled ? Color.FromArgb(115,121,132) : Primary ? DialogTheme.Background : Destructive ? DialogTheme.Danger : DialogTheme.Text;
            TextRenderer.DrawText(g,Text,Font,new Rectangle(8,0,Width-16,Height),color,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
            if(Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(g,new Rectangle(5,5,Width-10,Height-10),DialogTheme.Accent,BackColor);
        }
    }
    public sealed class ThemeComboBox : ComboBox {
        protected override void WndProc(ref Message message){
            base.WndProc(ref message);
            if(message.Msg==0x000F && IsHandleCreated){
                using(var graphics=Graphics.FromHwnd(Handle)){
                    int width=Math.Max(24,(int)(24*DeviceDpi/96f));
                    var bounds=new Rectangle(ClientSize.Width-width,0,width,ClientSize.Height);
                    using(var brush=new SolidBrush(DialogTheme.Input))graphics.FillRectangle(brush,bounds);
                    int x=bounds.Left+width/2,y=bounds.Height/2;
                    using(var brush=new SolidBrush(Enabled ? DialogTheme.Muted : DialogTheme.Border))graphics.FillPolygon(brush,new[]{new Point(x-4,y-2),new Point(x+4,y-2),new Point(x,y+2)});
                    using(var pen=new Pen(Focused ? DialogTheme.Accent : DialogTheme.Border))graphics.DrawRectangle(pen,0,0,ClientSize.Width-1,ClientSize.Height-1);
                }
            }
        }
    }
    public static class DialogTheme {
        public static Color Background=Color.FromArgb(23,25,29),Panel=Color.FromArgb(32,35,40),Input=Color.FromArgb(39,43,50),Hover=Color.FromArgb(48,53,61),Selection=Color.FromArgb(45,55,73);
        public static Color Text=Color.FromArgb(240,240,236),Muted=Color.FromArgb(160,165,175),Accent=Color.FromArgb(156,183,238),Border=Color.FromArgb(54,60,70),Success=Color.FromArgb(160,180,163),Warning=Color.FromArgb(222,181,125),Danger=Color.FromArgb(222,151,151);
        public static readonly Font Body=new Font("Segoe UI",10f),Caption=new Font("Segoe UI",9f),Strong=new Font("Segoe UI",10f,FontStyle.Bold);
        sealed class State { public int Hot=-1; }
        static readonly ConditionalWeakTable<Control,State> Styled=new ConditionalWeakTable<Control,State>();
        [DllImport("dwmapi.dll")]static extern int DwmSetWindowAttribute(IntPtr handle,int attribute,ref int value,int size);
        [DllImport("uxtheme.dll",CharSet=CharSet.Unicode)]static extern int SetWindowTheme(IntPtr handle,string app,string id);
        public static GraphicsPath Round(RectangleF r,float radius){
            var path=new GraphicsPath();var d=Math.Min(radius*2,Math.Min(r.Width,r.Height));
            path.AddArc(r.Left,r.Top,d,d,180,90);path.AddArc(r.Right-d,r.Top,d,d,270,90);path.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);path.AddArc(r.Left,r.Bottom-d,d,d,90,90);path.CloseFigure();return path;
        }
        public static Color Semantic(Color color) {
            if(color.ToArgb()==Color.FromArgb(30,125,70).ToArgb())return Success;
            if(color.ToArgb()==Color.FromArgb(155,95,20).ToArgb() || color.ToArgb()==Color.FromArgb(150,95,25).ToArgb())return Warning;
            if(color.ToArgb()==Color.Gray.ToArgb() || color.ToArgb()==Color.FromArgb(95,105,120).ToArgb() || color.ToArgb()==Color.FromArgb(75,85,100).ToArgb())return Muted;
            if(color.ToArgb()==Color.Black.ToArgb() || color.ToArgb()==SystemColors.WindowText.ToArgb() || color.ToArgb()==SystemColors.ControlText.ToArgb())return Text;
            return color;
        }
        public static void Apply(Form form){
            form.SuspendLayout();try{ApplyControl(form);}finally{form.ResumeLayout(true);}
            if(form.IsHandleCreated)Chrome(form);else form.HandleCreated+=(s,e)=>Chrome(form);
        }
        static void Chrome(Form form){
            try{int dark=1;DwmSetWindowAttribute(form.Handle,20,ref dark,4);int caption=ColorTranslator.ToWin32(Background);DwmSetWindowAttribute(form.Handle,35,ref caption,4);int foreground=ColorTranslator.ToWin32(Text);DwmSetWindowAttribute(form.Handle,36,ref foreground,4);}catch(DllNotFoundException){}catch(EntryPointNotFoundException){}
        }
        static bool IsPrimary(string text){return text.StartsWith("Prepare in Steam",StringComparison.OrdinalIgnoreCase)||text.StartsWith("Apply",StringComparison.OrdinalIgnoreCase)||text.StartsWith("Save",StringComparison.OrdinalIgnoreCase);}
        static void ApplyControl(Control control){
            State state;bool first=!Styled.TryGetValue(control,out state);
            if(first){state=new State();Styled.Add(control,state);}
            control.BackColor=Background;control.ForeColor=Semantic(control.ForeColor);
            if(control.Font.Size <= 12 && !(control is ToolStrip))control.Font=Body;
            var action=control as ActionButton;
            if(action!=null){action.Primary=action.Primary || IsPrimary(action.Text);action.Destructive=action.Text.StartsWith("Remove",StringComparison.OrdinalIgnoreCase);action.Invalidate();}
            else if(control is Button){var button=(Button)control;button.FlatStyle=FlatStyle.Flat;button.FlatAppearance.BorderColor=Border;button.BackColor=Input;button.ForeColor=Text;}
            if(control is TextBoxBase){var box=(TextBoxBase)control;box.BackColor=Input;box.ForeColor=Text;box.BorderStyle=BorderStyle.None;}
            if(control is LinkLabel){var link=(LinkLabel)control;link.ForeColor=Muted;link.LinkColor=Accent;link.ActiveLinkColor=Accent;link.VisitedLinkColor=Accent;}
            if(control is PictureBox){control.BackColor=Panel;}
            if(control is CheckBox){var check=(CheckBox)control;check.FlatStyle=FlatStyle.Flat;check.FlatAppearance.BorderColor=Border;check.FlatAppearance.CheckedBackColor=Accent;check.ForeColor=Text;}
            if(control is RadioButton){var radio=(RadioButton)control;radio.FlatStyle=FlatStyle.Flat;radio.BackColor=radio.Checked ? Selection : Input;radio.ForeColor=radio.Checked ? Accent : Text;if(first)radio.CheckedChanged+=(s,e)=>{radio.BackColor=radio.Checked ? Selection : Input;radio.ForeColor=radio.Checked ? Accent : Text;};}
            if(control is ComboBox){
                var combo=(ComboBox)control;combo.BackColor=Input;combo.ForeColor=Text;combo.FlatStyle=FlatStyle.Flat;combo.DrawMode=DrawMode.OwnerDrawFixed;combo.ItemHeight=Math.Max(combo.ItemHeight,Body.Height+6);
                if(first)combo.DrawItem+=(s,e)=>{if(e.Index<0)return;var selected=(e.State&DrawItemState.Selected)!=0;using(var brush=new SolidBrush(selected ? Selection : Input))e.Graphics.FillRectangle(brush,e.Bounds);TextRenderer.DrawText(e.Graphics,combo.GetItemText(combo.Items[e.Index]),Body,new Rectangle(e.Bounds.X+8,e.Bounds.Y,e.Bounds.Width-12,e.Bounds.Height),Text,TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);};
            }
            if(control is ListBox){
                var list=(ListBox)control;list.BackColor=Panel;list.ForeColor=Text;list.BorderStyle=BorderStyle.None;list.DrawMode=DrawMode.OwnerDrawFixed;list.ItemHeight=Body.Height+12;
                if(first)list.DrawItem+=(s,e)=>{if(e.Index<0)return;using(var brush=new SolidBrush((e.State&DrawItemState.Selected)!=0 ? Selection : Panel))e.Graphics.FillRectangle(brush,e.Bounds);TextRenderer.DrawText(e.Graphics,list.GetItemText(list.Items[e.Index]),Body,new Rectangle(e.Bounds.X+8,e.Bounds.Y,e.Bounds.Width-12,e.Bounds.Height),Text,TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);if((e.State&DrawItemState.Focus)!=0)e.DrawFocusRectangle();};
            }
            if(control is ListView){
                var list=(ListView)control;list.BackColor=Background;list.ForeColor=Text;list.BorderStyle=BorderStyle.None;list.GridLines=false;
                if(first){list.HandleCreated+=(s,e)=>{try{SetWindowTheme(list.Handle,"DarkMode_Explorer",null);}catch(DllNotFoundException){}catch(EntryPointNotFoundException){}};}
                if(list.View==View.Details && !list.CheckBoxes){
                    list.OwnerDraw=true;
                    if(first){
                        if(list.SmallImageList==null){var images=new ImageList();images.ImageSize=new Size(1,34);list.SmallImageList=images;list.Disposed+=(s,e)=>images.Dispose();}
                        list.DrawColumnHeader+=(s,e)=>{using(var brush=new SolidBrush(Panel))e.Graphics.FillRectangle(brush,e.Bounds);TextRenderer.DrawText(e.Graphics,e.Header.Text.ToUpperInvariant(),Caption,new Rectangle(e.Bounds.X+10,e.Bounds.Y,e.Bounds.Width-12,e.Bounds.Height),Muted,TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);};
                        list.DrawItem+=(s,e)=>{};
                        list.DrawSubItem+=(s,e)=>{
                            var fill=e.Item.Selected ? Selection : e.Item.Index==state.Hot ? Panel : Background;
                            using(var brush=new SolidBrush(fill))e.Graphics.FillRectangle(brush,e.Bounds);
                            var textColor=e.Item.Selected ? Text : Semantic(e.SubItem.ForeColor);
                            TextRenderer.DrawText(e.Graphics,e.SubItem.Text,e.ColumnIndex==0 ? Strong : Body,new Rectangle(e.Bounds.X+10,e.Bounds.Y,e.Bounds.Width-14,e.Bounds.Height),textColor,TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
                            if(e.ColumnIndex==0 && e.Item.Selected)using(var brush=new SolidBrush(Accent))e.Graphics.FillRectangle(brush,e.Bounds.Left,e.Bounds.Top+8,3,Math.Max(1,e.Bounds.Height-16));
                        };
                        list.MouseMove+=(s,e)=>{var item=list.GetItemAt(e.X,e.Y);int hot=item==null ? -1 : item.Index;if(hot!=state.Hot){state.Hot=hot;list.Invalidate();}};
                        list.MouseLeave+=(s,e)=>{state.Hot=-1;list.Invalidate();};
                    }
                }
            }
            if(control is ToolStrip){StyleStrip((ToolStrip)control);}
            if(control.ContextMenuStrip!=null)StyleStrip(control.ContextMenuStrip);
            if(first)control.ControlAdded+=(s,e)=>ApplyControl(e.Control);
            foreach(Control child in control.Controls)ApplyControl(child);
        }
        static void StyleStrip(ToolStrip strip){
            strip.BackColor=Background;strip.ForeColor=Text;strip.Renderer=new ToolStripProfessionalRenderer(new Colors());
            foreach(ToolStripItem item in strip.Items)StyleItem(item);
        }
        static void StyleItem(ToolStripItem item){
            item.BackColor=Panel;item.ForeColor=item.Text.StartsWith("Remove",StringComparison.OrdinalIgnoreCase) ? Danger : Text;item.Font=Body;
            var drop=item as ToolStripDropDownItem;if(drop!=null){drop.DropDown.BackColor=Panel;drop.DropDown.Renderer=new ToolStripProfessionalRenderer(new Colors());foreach(ToolStripItem child in drop.DropDownItems)StyleItem(child);}
        }
        sealed class Colors : ProfessionalColorTable {
            public override Color ToolStripDropDownBackground{get{return Panel;}} public override Color MenuBorder{get{return Border;}}
            public override Color ImageMarginGradientBegin{get{return Panel;}}public override Color ImageMarginGradientMiddle{get{return Panel;}}public override Color ImageMarginGradientEnd{get{return Panel;}}
            public override Color MenuItemSelected{get{return Selection;}}public override Color MenuItemBorder{get{return Border;}}
            public override Color MenuItemSelectedGradientBegin{get{return Selection;}}public override Color MenuItemSelectedGradientEnd{get{return Selection;}}
            public override Color MenuItemPressedGradientBegin{get{return Panel;}}public override Color MenuItemPressedGradientMiddle{get{return Panel;}}public override Color MenuItemPressedGradientEnd{get{return Panel;}}
            public override Color SeparatorDark{get{return Border;}} public override Color SeparatorLight{get{return Panel;}}
        }
        public static Form CreateMessageBox(string text,string title,MessageBoxButtons buttons,MessageBoxIcon icon){
                var dialog=new Form();
                dialog.Text=title;dialog.ClientSize=new Size(530,300);dialog.MinimumSize=new Size(450,250);dialog.StartPosition=FormStartPosition.CenterParent;dialog.Font=Body;dialog.MinimizeBox=false;dialog.MaximizeBox=false;
                var panel=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(24),ColumnCount=1,RowCount=3};panel.RowStyles.Add(new RowStyle(SizeType.Absolute,38));panel.RowStyles.Add(new RowStyle(SizeType.Percent,100));panel.RowStyles.Add(new RowStyle(SizeType.Absolute,44));dialog.Controls.Add(panel);
                var heading=new Label{Text=title,Font=new Font("Segoe UI",16f,FontStyle.Bold),Dock=DockStyle.Fill};panel.Controls.Add(heading,0,0);
                var body=new TextBox{Text=text,ReadOnly=true,Multiline=true,ScrollBars=ScrollBars.Vertical,BorderStyle=BorderStyle.None,Dock=DockStyle.Fill};panel.Controls.Add(body,0,1);
                var actions=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.RightToLeft};panel.Controls.Add(actions,0,2);
                DialogResult[] values=buttons==MessageBoxButtons.YesNo ? new[]{DialogResult.No,DialogResult.Yes} : buttons==MessageBoxButtons.YesNoCancel ? new[]{DialogResult.Cancel,DialogResult.No,DialogResult.Yes} : buttons==MessageBoxButtons.OKCancel ? new[]{DialogResult.Cancel,DialogResult.OK} : new[]{DialogResult.OK};
                foreach(var value in values){var button=new ActionButton{Text=value.ToString(),DialogResult=value,Width=100,Height=36,Margin=new Padding(8,4,0,0),Primary=value==DialogResult.Yes || value==DialogResult.OK};actions.Controls.Add(button);if(value==DialogResult.No || value==DialogResult.Cancel)dialog.CancelButton=button;else if(value==DialogResult.OK)dialog.AcceptButton=button;}
                Apply(dialog);
                // Confirmation defaults remain conservative: Enter never silently approves Yes.
                if(buttons==MessageBoxButtons.YesNo){foreach(Control control in actions.Controls){var button=control as Button;if(button!=null && button.DialogResult==DialogResult.No){dialog.AcceptButton=button;dialog.ActiveControl=button;}}}
                return dialog;
        }
        public static DialogResult ShowMessageBox(IWin32Window owner,string text,string title,MessageBoxButtons buttons,MessageBoxIcon icon){using(var dialog=CreateMessageBox(text,title,buttons,icon)){return dialog.ShowDialog(owner);}}
        public static DialogResult ShowMessageBox(IWin32Window owner,string text,string title,string buttons,string icon){return ShowMessageBox(owner,text,title,(MessageBoxButtons)Enum.Parse(typeof(MessageBoxButtons),buttons),(MessageBoxIcon)Enum.Parse(typeof(MessageBoxIcon),icon));}
    }
}
