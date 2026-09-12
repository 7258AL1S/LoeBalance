using LoeBalance.Core.Presentation;

namespace LoeBalance.Core.Tests;

public sealed class TaskbarBalanceGeometryTests
{
    // Real measurements from a Windows 11 taskbar: 2048x48 at the bottom of the screen with
    // the notification area starting at x=1678.
    private static readonly ScreenRect BottomTaskbar = new(0, 1232, 2048, 48);
    private static readonly ScreenRect BottomTray = new(1678, 1232, 370, 48);

    [Fact]
    public void BottomTaskbarPlacesTheReadoutLeftOfTheNotificationArea()
    {
        var placed = TaskbarBalanceGeometry.Place(BottomTaskbar, BottomTray, 96, 24, TaskbarEdge.Bottom);

        Assert.Equal(1678 - 96 - 8, placed.X);
        Assert.Equal(1232 + ((48 - 24) / 2), placed.Y);
        Assert.Equal(96, placed.Width);
        Assert.Equal(24, placed.Height);
        Assert.True(placed.Right <= BottomTray.X);
        Assert.True(placed.Bottom <= BottomTaskbar.Bottom);
    }

    [Fact]
    public void TopTaskbarUsesTheSameHorizontalRule()
    {
        var taskbar = new ScreenRect(0, 0, 1920, 40);
        var tray = new ScreenRect(1560, 0, 360, 40);

        var placed = TaskbarBalanceGeometry.Place(taskbar, tray, 90, 22, TaskbarEdge.Top);

        Assert.Equal(1560 - 90 - 8, placed.X);
        Assert.Equal((40 - 22) / 2, placed.Y);
    }

    [Fact]
    public void VerticalTaskbarSitsAboveTheTrayBlock()
    {
        var taskbar = new ScreenRect(0, 0, 48, 1080);
        var tray = new ScreenRect(0, 900, 48, 180);

        var placed = TaskbarBalanceGeometry.Place(taskbar, tray, 40, 90, TaskbarEdge.Right, gap: 4);

        Assert.Equal(4, placed.X);
        Assert.Equal(900 - 90 - 4, placed.Y);
        Assert.True(placed.Bottom <= tray.Y);
    }

    [Fact]
    public void OversizedReadoutIsPinnedInsideTheTaskbar()
    {
        var placed = TaskbarBalanceGeometry.Place(BottomTaskbar, BottomTray, 4000, 400, TaskbarEdge.Bottom);

        Assert.Equal(BottomTaskbar.X, placed.X);
        Assert.Equal(BottomTaskbar.Y, placed.Y);
    }

    [Fact]
    public void EdgeDetectionMatchesTheMonitorEdge()
    {
        var monitor = new ScreenRect(0, 0, 2048, 1280);

        Assert.Equal(TaskbarEdge.Bottom, TaskbarBalanceGeometry.EdgeFor(monitor, BottomTaskbar));
        Assert.Equal(TaskbarEdge.Top, TaskbarBalanceGeometry.EdgeFor(monitor, new ScreenRect(0, 0, 2048, 40)));
        Assert.Equal(TaskbarEdge.Right, TaskbarBalanceGeometry.EdgeFor(monitor, new ScreenRect(2000, 0, 48, 1280)));
        Assert.Equal(TaskbarEdge.Left, TaskbarBalanceGeometry.EdgeFor(monitor, new ScreenRect(0, 0, 48, 1280)));
    }

    [Fact]
    public void FallbackTrayRectKeepsTheReadoutAwayFromTheClock()
    {
        var fallback = TaskbarBalanceGeometry.FallbackTrayRect(BottomTaskbar, TaskbarEdge.Bottom);
        var placed = TaskbarBalanceGeometry.Place(BottomTaskbar, fallback, 96, 24, TaskbarEdge.Bottom);

        Assert.Equal(BottomTaskbar.Right, fallback.Right);
        Assert.True(placed.Right <= fallback.X);
        Assert.True(placed.X > BottomTaskbar.X);
    }

    [Fact]
    public void ReadoutWindowReservesTheAnimationStripAndSharesThePillCentre()
    {
        var pill = TaskbarBalanceGeometry.Place(
            BottomTaskbar,
            BottomTray,
            width: 60,
            height: TaskbarBalanceGeometry.PillHeight,
            TaskbarEdge.Bottom);

        var window = TaskbarBalanceGeometry.ReadoutWindow(pill, TaskbarBalanceGeometry.ReadoutWindowHeight);

        Assert.Equal(pill.Width + TaskbarBalanceGeometry.DamageAreaWidth, window.Width);
        Assert.Equal(TaskbarBalanceGeometry.ReadoutWindowHeight, window.Height);
        Assert.Equal(pill.Y + (pill.Height / 2), window.Y + (window.Height / 2));
        Assert.Equal(54, TaskbarBalanceGeometry.DamageAreaWidth);
        Assert.True(window.Y < pill.Y);
    }

    [Fact]
    public void WholeReadoutStaysClearOfTheNotificationArea()
    {
        const double pillWidth = 74;
        var totalWidth = pillWidth + TaskbarBalanceGeometry.DamageAreaWidth;

        var windowFrame = TaskbarBalanceGeometry.Place(
            BottomTaskbar,
            BottomTray,
            totalWidth,
            TaskbarBalanceGeometry.PillHeight,
            TaskbarEdge.Bottom);

        // Pill plus strip must end before the tray/clock block, otherwise the floating
        // numbers would cover the tray icons and the overflow chevron.
        Assert.True(windowFrame.Right <= BottomTray.X);
        Assert.Equal(8, BottomTray.X - windowFrame.Right);
        Assert.True(windowFrame.X > BottomTaskbar.X);
    }
}
