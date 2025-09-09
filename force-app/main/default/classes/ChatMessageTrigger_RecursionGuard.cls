public class ChatMessageTrigger_RecursionGuard {
    private static Boolean ran = false;
    public static Boolean runOnce() {
        if (ran) return false;
        ran = true;
        return true;
    }
}

