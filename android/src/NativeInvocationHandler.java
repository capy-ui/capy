import java.lang.Object;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;

public class NativeInvocationHandler implements InvocationHandler {
  public NativeInvocationHandler(long ptr) { this.ptr = ptr; }

  public Object invoke(Object proxy, Method method, Object[] args) {
    return invoke0(proxy, method, args);
  }

  native private Object invoke0(Object proxy, Method method, Object[] args);

  private long ptr;
}
