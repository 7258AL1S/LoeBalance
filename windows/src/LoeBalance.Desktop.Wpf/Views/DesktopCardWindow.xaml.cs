using System.Windows;
using LoeBalance.Core.Models;

namespace LoeBalance.Desktop.Wpf.Views;

public partial class DesktopCardWindow : Window
{
    public DesktopCardWindow() => InitializeComponent();

    public void Present(BalanceSnapshot snapshot) => BalanceText.Text = snapshot.Balance.CurrencyText;
}
