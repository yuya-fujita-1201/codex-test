public class ChatMessageTrigger_RecursionGuard {
    private static Boolean ran = false;
    public static Boolean skipOutbound = false; // Controllerから同期連携する場合に、トリガでの外部連携を抑止するためのフラグ
    public static Boolean runOnce() {
        if (ran) return false;
        ran = true;
        return true;
    }
}
