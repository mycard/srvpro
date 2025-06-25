export async function retry<T>(
  fn: () => Promise<T>,
  count: number,
  delayFn: (attempt: number) => number = (attempt) => Math.pow(2, attempt) * 100
): Promise<T> {
  let lastError: any;

  for (let attempt = 0; attempt < count; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (attempt < count - 1) {
        const delay = delayFn(attempt);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  // 如果全部尝试失败，抛出最后一个错误
  throw lastError;
}
