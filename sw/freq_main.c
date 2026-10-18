/*
 * Частотомір: програма для MicroBlaze (крок 6 курсового проєкту).
 *
 *  1. записує тривалість вікна в WINDOW (у тактах системного клока);
 *  2. запускає вимірювання записом 1 у CTRL;
 *  3. у циклі читає STATUS, поки він не стане 1;
 *  4. читає COUNT і обчислює частоту: f = COUNT / (WINDOW / CLK_HZ) = COUNT * CLK_HZ / WINDOW.
 *
 * Результати лежать у глобальних змінних (їх видно в налагоджувачі):
 *    result_count, result_freq_hz, result_done (1 після завершення).
 * UART у системі немає, тому друку немає.
 */

#include "xparameters.h"
#include "xil_io.h"
#include "xil_types.h"

#if defined(XPAR_FREQ_COUNTER_0_BASEADDR)
  #define FC_BASE XPAR_FREQ_COUNTER_0_BASEADDR
#elif defined(XPAR_FREQ_COUNTER_0_S_AXI_BASEADDR)
  #define FC_BASE XPAR_FREQ_COUNTER_0_S_AXI_BASEADDR
#else
  #error "Не знайдено базову адресу freq_counter у xparameters.h"
#endif

/* Зсуви регістрів IP */
#define REG_WINDOW  0x00   /* запис/читання: тривалість вікна, такти */
#define REG_CTRL    0x04   /* запис: 1 у розряд [0] запускає вимірювання */
#define REG_COUNT   0x08   /* читання: кількість фронтів за вікно */
#define REG_STATUS  0x0C   /* читання: розряд [0] = 1, вимірювання завершене */

#define CLK_HZ      100000000u   /* системний такт, 100 МГц */
#define WINDOW_CLKS 1000u        /* вікно 1000 тактів = 10 мкс */

volatile u32 result_count   = 0;
volatile u32 result_freq_hz = 0;
volatile u32 result_done    = 0;

int main(void)
{
    Xil_Out32(FC_BASE + REG_WINDOW, WINDOW_CLKS);
    Xil_Out32(FC_BASE + REG_CTRL, 1);

    while ((Xil_In32(FC_BASE + REG_STATUS) & 0x1) == 0) {
        /* чекаємо завершення вимірювання */
    }

    u32 count = Xil_In32(FC_BASE + REG_COUNT);
    result_count   = count;
    result_freq_hz = (u32)(((u64)count * CLK_HZ) / WINDOW_CLKS);
    result_done    = 1;

    while (1) {}
    return 0;
}
