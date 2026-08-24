// ============================================================
// Verifica os 114 pares de pastas duplicadas que sobraram (ambos
// "Concluído" na fila — por isso a limpeza anterior não mexeu neles).
// Conta os mp3s de cada lado (recursivo, incluindo subpastas) e grava o
// resultado numa aba nova "VerificacaoDuplicatas" na mesma planilha de
// controle da migração, com uma recomendação por linha.
//
// NÃO apaga nada — só investiga e relata. A decisão de excluir vem depois,
// olhando os resultados.
//
// Como usar:
//   1. Cole este arquivo no MESMO projeto Apps Script do CopiaMusicas
//      (o que já tem processarLote, e a propriedade PLANILHA_ID salva).
//   2. Rode a função verificarDuplicatasRestantes().
//   3. Se parar no meio (aviso "⏸️ Tempo esgotado"), rode de novo — ela
//      pula os pares que já foram processados e continua de onde parou.
//   4. Quando aparecer "🎉 CONCLUÍDO!", os resultados estão na aba
//      "VerificacaoDuplicatas" da planilha Log_Copia_Musicas.
// ============================================================

var PARES_VERIFICAR = [
  { origemId: '1tqATNJo8sB8K9HWE5USYzm-ehmx6HnFE', destinoA: '10Aa1zXybr5CMN28a36QL9pvt8OynXdHb', destinoB: '1G9Aru7qtHwaXdURs7oLi0Wpa3rv6smFc' },
  { origemId: '1X4Jgcc4YHtoArB2uAIK6LoC583uTpB-q', destinoA: '1PwjESNmlpgAKKx5KnuWM5JaRek_2du51', destinoB: '1krnNlNrmX2GVpcwQ_fUsOipi1m6oWnu7' },
  { origemId: '1KOrFAYriw0izgeo0V06ivhoW8kgyM3V8', destinoA: '1CcjLSKeJq31hqIZtgkM7-afiNaIU6BhL', destinoB: '1n33i46QdzkTsmHNtpEEKgcQj9aGNnFwM' },
  { origemId: '1OLIGq64O3beZ_zR_rFwQvWohaDYJkouy', destinoA: '1MXyI6ECnzMW4l4hNjAtJEqgCJ0YrUbXb', destinoB: '1h9aBMKJkNFPZnZH54TklzPbZEqybH760' },
  { origemId: '1bPYHcbq71L126e87ffFql6QJ_OQZVvPJ', destinoA: '1JR8YoxUcOVXYyCm9XgVJXMs14KGa5gXT', destinoB: '1lF510nL0hmI3W-pMXmdDYj7MQ2Wfe0ni' },
  { origemId: '1nHqycSNPWUsc3d_AmFaJs2scVGyUfLwj', destinoA: '1hirW80R_HEVckBvmc-gF3U6UyLt-Lslz', destinoB: '1Qgi95VDVbwPAjrM0ffsRDjUPDXFZ9l4q' },
  { origemId: '1YBcZ376ucDTGiug2zDZdt6ayzLmu6LxL', destinoA: '1uzRWKroaw-xxf3nEdDz9CWh_Sy30ZoCj', destinoB: '1WRwrfSyiti3OYxmuR1IOhWH3LDmnpj3J' },
  { origemId: '1tGdTA-dB75gWG-Pbw2462bB000cn3o3C', destinoA: '1ImtKlUHIGiTts3e4A61bJwMNSWqmskts', destinoB: '1Rj4NJLsW-PO-E1aSPZJd--DRtbHjoaxd' },
  { origemId: '1fYhjAwfL4QzFHvQvuUVwoqe7FMIvGbEV', destinoA: '1TpQm2eznHhXLM4K2fe6YtS2wnyyImr53', destinoB: '1kvqK6vUmZ9c7PcF0Lekd3wI6irg_reYn' },
  { origemId: '13rTNs4mNXQV4Z6mF5H_8zN1CcaxcmdUp', destinoA: '14M1bY9ayYQP5LFxycLGFxIO_otQrKvpY', destinoB: '1oytJmNeLDN5TJkvQCXvO2ucp7eKZ5AD7' },
  { origemId: '11S_0c42xWHuB7nk6-49iYCD6IcxYl0Hc', destinoA: '13iY2Hreh_Z-VU56eHZSVMqsA51Qq2s7B', destinoB: '1iNVklWn9pNer21V3nRIfd1dKBpkAOVnx' },
  { origemId: '1qDrDRuyy5oP8Sgbfc6PBaFzMudK_uTH4', destinoA: '1zl3eut0Ve9r19iJMdvqyoPQJSeugHIb1', destinoB: '1eUH2sjyg_JdH6Td1etiVsFlrAhmVfuQN' },
  { origemId: '1P7zkBKemyKyEgHCnY8JeNaD9GzuuZyx9', destinoA: '16xaAlVlh-C1L710JNAamuFnn7jlm50fy', destinoB: '1FE_qN_Mws1cNRfu4KWoXmUjRxAyDacH4' },
  { origemId: '1abtnAzVmi7c4ih2bsYkd-jLpYov4LBft', destinoA: '1PpHNkYocnQa5LxkbZRFVlMQbk9jmy7pS', destinoB: '1nqgkKSF79s4-PFtXMPDELA9z1Bksi1V_' },
  { origemId: '1Mz9eQux1pXqXKY4a5hafFc-zS5OUVyiv', destinoA: '10895c7cM4LaWsAHYLtgYpRLA2gl1-nvD', destinoB: '1aq_VMXolvyAsKAZxpgdcZRyRhNkBRMs3' },
  { origemId: '1bbJ4-p3kF74_GXMsF2qih--9Em-iL1tO', destinoA: '10p92gqZ1ELZpgkHsunI_5QotCYFUfP75', destinoB: '1MfcjQd17tex0soDFQezMFsGowDxfaCBc' },
  { origemId: '1tIPVhJmsA8r-3tJPsmonfrikoMJ8J7Zz', destinoA: '1mPKwUyv_ksyFRwmpEKT3CaEjcRduZgwE', destinoB: '1b8HfDn9GSTYJGJ0F1jCPlse70hLyKPx3' },
  { origemId: '1PbND6yPKy4b_tY7DCgwOVvIvD1LCGVDB', destinoA: '1JuADpG_vhGYJFed13mCoHB8g4dPmxbS3', destinoB: '1QyB2mrch79cEZIKdjwJEfrLec_9mkczf' },
  { origemId: '1rVv0aXZPPj4c_TKTCIPfGBapkk1_DunL', destinoA: '1tcFWnvgd5qhlpafLX5Xg5OkqHeixSS0E', destinoB: '1_tRbl7klyG_9U6Q5h75dVrYmIR5UKbww' },
  { origemId: '1c_v5YwtG6UhDQufLZSOfnBCUXhb4hBLk', destinoA: '1yHIOhlS8Cmvz24FPV26BPEe6xqosfjzX', destinoB: '11rEjNo2cocmfCAjB_Kj3gpQTFdSK1tAq' },
  { origemId: '1BrdKgOVbkajMsTC18utfTP18KJHOQ4WM', destinoA: '1mBtf88UdbCE_YbjNvWaYrd5XhLigDA9M', destinoB: '1PIkKfUkt4sR2ly_2WdrD8uvBUVi_S3nE' },
  { origemId: '1xL1xD-DYGi5Wi9y_J_nxIGYIs3Q_zGiS', destinoA: '1JlnvbKpKutMpcZQr-M4WDuFEvgIcMkJj', destinoB: '1VzDStDLaC4WYCFWeXCaqJGdkzOx3N_SP' },
  { origemId: '1hpLeRwOqAxo9zcW7jf7P2N4a1d2IdJHD', destinoA: '1pPBR3rh43zakjf0Ge_JLBY7ciXoje2AP', destinoB: '1Atdo2YJMDfkttqXNCMw9NCtZTYusgncg' },
  { origemId: '1fnq1bPQntKERtIi7SCC2sjqFoasCZw6a', destinoA: '132E6cjoP0cI4nj21TSv8QitzmLeM4UaJ', destinoB: '14sIRB_HTpr7MgUMPE4fRLUH4RgdMeD9n' },
  { origemId: '1iy-FQCsGpkaQ8jbX8OM_s-3gfAUCfX6z', destinoA: '1WuFRnoolBmaqz5LVql91awThdP96Qz_7', destinoB: '1sbV8j5OB-Wq-Srm4N89pksat9aduS8ZD' },
  { origemId: '1UYux-arJ71HJuJfNYiJwYolenFdvOjfU', destinoA: '1xok7NsWz6fLb-W0ql2PMR9d6rILAon0r', destinoB: '1_2u5BK65vYqJUSsW_JT-pyghYn5ERHJC' },
  { origemId: '1ZZzbvKLtg8KmxP1oqQR8_1kUmF2sjfsa', destinoA: '1UHVG8y4u0EXQ2tdBvUDLwuxwnhWP5k34', destinoB: '1RQf2NMCgqww3BkXSoKJhVYQisFNA8EZy' },
  { origemId: '1I0nak4XTqAoSehXrMIm6tCbtaaR9bGUj', destinoA: '1F0Ge8WCYysUAmjsCnC29s9_yDZGhbmF_', destinoB: '1tbUp-ww_TYs_iQBxrac7adMklwvSquSD' },
  { origemId: '18B-_inhmBknkxC-OSEIVU-cAfWrROGvs', destinoA: '1ks94tU2QsuOwHXUt0xp9IUWaWBNEspqC', destinoB: '1XxZt56W7gLgPsPR7xHbdV4d6ntZBVfow' },
  { origemId: '1rE_s26yalMzgjOfgG06b3ZFOrWL3Alwx', destinoA: '1S7rzvO3ZnjEN_anZN2U7ONWzyKeD2INf', destinoB: '1tJhsZx9Tn68s0ZeC0EGJB2IgAE1QHJuv' },
  { origemId: '1VY40AnfiEU4wHkR-QZlyqtVmni75jd9A', destinoA: '1lnUA3EsKSRmk99qXlY8PkTcbn7lyPtR5', destinoB: '13lauzv4cdlTdlxdrpstqVxWTwLSU84GS' },
  { origemId: '1nUcNDu_Szh5xvTnWgdbs17ZUvfOo9IfT', destinoA: '1zZCbWCYSrcOZgvoKWkIp9JJh4aixocS-', destinoB: '1e-4nv8gH50a695O7pPB2H_eEEKpnc83i' },
  { origemId: '1soHYjUSKbuiwOWhfloeE04hcnb_btJMD', destinoA: '1gR4MQvCDh9lnmzeQC7ZiaQ9HNn6dWeVK', destinoB: '1vjd4u5KIUwNlTiGxqOyiMgo_WgQPfDB0' },
  { origemId: '1A_qjsdmbfrgjXs-icUNgg3GMYMLYO-zw', destinoA: '19IMG2yQQkRv1I4SxS8vLoE9l_aXOy0rt', destinoB: '1yRlAVTzWIizq73HPLjF-m5BYrGj7EIzg' },
  { origemId: '1ez8-XFhQYq8FUw52K9hh2OLzJxWSJZhQ', destinoA: '11qKUdRyVxrJFne_nTcubTWUzUSoC3Z3v', destinoB: '14eYJQ4LqeDCryr8V9BibBxBAL35bXO9J' },
  { origemId: '19Wn3qLzqWkjMAWgLHo39DuA5Y7AqD8Qo', destinoA: '1cuoj_WXpfvTDlKZyrJjmpyPgR_lV8QKv', destinoB: '1OqebazWoyuSDoHCbKrzJbdJFt66OUmiH' },
  { origemId: '1YIdakjxe8C1VGdW6QJAw-vOcKxBoVtxq', destinoA: '1QvAmJkvURfgZasibaYkdw0r9fWW7Okqn', destinoB: '1HQtxNMHHniTwO5_UODInalBcnahE7-uU' },
  { origemId: '1szFhL_HPfbxz6R-JH_f4PvQ-oVKnwCDH', destinoA: '1LlwZ7nphteoxns0MDfq1sRzZmiMHXOfE', destinoB: '1DRIRPMvVAR9BOpN8R1qJi5VR60LvuLZX' },
  { origemId: '1ZDbiormY1jjX_0TvRdQxokXoS6fKqgtn', destinoA: '12yX0Zn7MKl-6uLIUWCfUO0OzTEBQWmiu', destinoB: '1RrmKtlgkJAF2fsh_4YsrhzX7vpveLECU' },
  { origemId: '1LC0KrWntds3p-6PnzLccJS8Fr4nWvLKY', destinoA: '1VytOMcgQw8NGJ0EzG3uvQ6Q5SOb59Wvb', destinoB: '1xDxTaHoA-ipyxJSFEHK6rqYz1rgiTC_T' },
  { origemId: '1jPjLZtctQ_YRXD2PE_vjrBepXnOkOXWX', destinoA: '1NC0FJ5p8L3mKmTMfYMCm24TvAWpJ0XmO', destinoB: '1-h2XtfO70aoYRKLJpC5T3RohyUNAhjON' },
  { origemId: '1ZHmtK6BXDTPSj9-cUJzEJQI0kXAKL4ua', destinoA: '1FOo7bXM5XyeEioHesT0cueCNi7cstABZ', destinoB: '1d0kMV2FlpnohUTW3um9mGz4T7xyjCe85' },
  { origemId: '1w5LIQ9yh-Yq1gIXvYm_Yn8PzbYQlqX_K', destinoA: '1Yx4wa5U5Mz_VbqxfIWNl2i3hsTbr-pF_', destinoB: '1H1xMllupEZv_Amu_SLQL8BdAkI-J5ncc' },
  { origemId: '1gKG9-70yQBdZhiXpPq855Sm8qlFPi0P6', destinoA: '1p-IoWDrfD3KbOvadftlBtC-p-IMxfFCF', destinoB: '1iLErF84wMGJ_KLUl3Apuyv4mtbDxhwlE' },
  { origemId: '1PhipZx_9YvkQwIle_JhMNic7vz2M3OFq', destinoA: '1xqcb33OleTkvycFh45QFMh0PToXO-mx7', destinoB: '1jzDMji8cGePVwFoXVTqEtJgV3ygNYhlE' },
  { origemId: '1D8F3xQNS9ud6fFH_78UX_LmoMxo4qQ8m', destinoA: '1TvPRco6ImjIhf0idMp2mHkXXNMbyzRcJ', destinoB: '1Yks3UfUGvcUu-OPPJ4wjertW0qrxnqkf' },
  { origemId: '1WnuuuTe-lVgh2NJEFrLjrmh1Ruf_5bFY', destinoA: '1FCT_vAOdindv9dUMaa6IMPl_1WWFThEa', destinoB: '1oyAxF3Dft69MZc0_1xxgm344OBUGWgIM' },
  { origemId: '1bCMfS_KiAhAOWjoRkeEOfcdkruH4Ne5j', destinoA: '1O_iCDRMPCdDw1qyLcRvIfXsjW6KoAmcB', destinoB: '1CfxaFaoXdQzkvuHdRYjnmFMwlX6xFQ3W' },
  { origemId: '1O3O5T3ZDgyRJrur5QU7-ognM8NrfDs_X', destinoA: '1FOz8RmE0lVVSUp6prmqAJel1qzFOEXBg', destinoB: '1kgg4A3BsjDBf-O7G0ATQKHKQWhD7Q-3d' },
  { origemId: '1F5FX9LjC3N1QnSPEKqDZ09TbPFhNKedl', destinoA: '1cwzRsg4Spdn0ZyDTSunsg7mZ7o20-Plv', destinoB: '1R2aFX-Rw5biFR5dhDrhOw8vZD5xrCnlf' },
  { origemId: '1l0oAM15N-W2fVB2RFuXFFc7OEQGAm6Hz', destinoA: '13NssAg47-tVXK1SdQCzIJyuOcSgFfoMI', destinoB: '1nft0Kl9wR9VlGKiXUMXayoYhU9A2iykG' },
  { origemId: '1RaIUvVA6amOFETCTKI-QnUC2ttAbHuIj', destinoA: '1j81alxdOz4-7dmnUN6J0lZtxjGHTTGng', destinoB: '12b0KiK9uBrOYTlTKufkCO85-_ojI8sEP' },
  { origemId: '1NWonmsN6LetCHal88lhHamwjngKji2Mm', destinoA: '14vy-exh2xQte3r_clP0aYmnQtMHTVi9L', destinoB: '1bCO8S9HkePmrQYv55kvgWO-_R8PhJ34i' },
  { origemId: '16X4Lv2KAdTELmuhDF7Ip0QPy8vtGtCus', destinoA: '16hywawB8w5E8FZPRPGxLiCYZFgsagWfx', destinoB: '1oDx-WaQaiWQiyoySpHLpSgoJy7KtXc1B' },
  { origemId: '1GEMAI7uRKT8gL7erjzwWt1UnwFy2PiT6', destinoA: '1qaIig_XarKeHa6O9MBTlCqmsQa6xopxJ', destinoB: '1trGI1kdGcFnIY_KQl4AJ2xjaoDN9c4_u' },
  { origemId: '1mcpw_66YTGj9FYLFUKizTm-1NfN7cPpx', destinoA: '12Q4QDlPPR_UcFpxiwHXGe8eQvDlyU1_G', destinoB: '19Ei3b9qDqdv8H6p6L7QsUnuD8ZdjRF5J' },
  { origemId: '15tweB_UWIIlQ_QFVpRvx4HKidw9sr7NL', destinoA: '1nDbA2wSmXes_WQu77SCMXca_dRzlWME_', destinoB: '19iaXFSbfyyu1jOmvJYicSGfhQXBHjrut' },
  { origemId: '1MOcEOd1e3lWmj6YpsCguFrs9WAPc0cSv', destinoA: '1BBUfJmkmz-5YG59NXQMEWC_IgqQcPfkx', destinoB: '1RazdxGNFOuLFA2B-chMnd7svtt9B99_m' },
  { origemId: '1Mx_GjYPsLWj8GV5OAf6JP9EKhZqbUsag', destinoA: '1_xoaoYLF7tJ3ADWRPcbg4UfvXtvt5jC0', destinoB: '1aqEXCgNKKY0Q8tWp_L4wI4FxxK1vqK6g' },
  { origemId: '1yQvjGUV31G2sd3C3JZJHhUTpJO1JU4Ic', destinoA: '1sRYTSWI4dO3R26tKz-3U7YTDAmStl3bN', destinoB: '18PaL9NZuuuq93Sx8O5F3nxw5MlD2EdIj' },
  { origemId: '1QycMhbgonkj0UNzQNEIEjI2G5ObdcDQA', destinoA: '1JEf3Era6CGI5G4IZamrBCA3DkHd800CL', destinoB: '1ES_4wYeFymKyP6QiHb7R628PFWs90tR-' },
  { origemId: '1bM95-L796K2u6SscwV4uj-M6HdhYzbCB', destinoA: '1HxkDV4SXi9owELXKrKBOLJ8b3QkGjEin', destinoB: '1DSM31HUsJe7BJxKrV67n6bk9e_VC3wJd' },
  { origemId: '1cT-2Zr0v3xSX9PdGbFe7tm2QYm7La88x', destinoA: '1fiOK54AwtFlTbWWC5G-bOLozMpgdvTsq', destinoB: '1rL26zXGamJOin2P5rWYIP8gKkREXJMuV' },
  { origemId: '1ezjC86hVzlVdIzRKl2xEQPelYz6fkpN1', destinoA: '1ZuYYRm_Au_gqii2j1jTtOGnaGDE3Wbzc', destinoB: '1abpcAl99tjRKkd96FomleJ8bKkgAlik1' },
  { origemId: '12QtBSJIampLx3VwM5IiFSCVUA3y36NUD', destinoA: '1YSw2sVZYN4oPtq4sfuSU59lwhYP5FNxb', destinoB: '1HOc7SsoXvD0x1fsvZmmx8tNQesaD_bFK' },
  { origemId: '1pxRt51VLyxsknYshRoQCiO86oVNH4BFH', destinoA: '1e9dK0VCIejuV6uwAYCabrc_U52Wmg23s', destinoB: '1getxInV8Ghne8vnZuq2WtH15X2yUGcmk' },
  { origemId: '1jjEvMYizGqf_RlxcvDEBKG53u5MdcnRv', destinoA: '1yYm1k-0ZDXT7rqS2NPyU61raNFNrRRiY', destinoB: '1_udngQZWG9oOpjP_pm7vUoP7KryTKELe' },
  { origemId: '1q9ehivlAMMoRid81C9UMrdeQpLkNMgOs', destinoA: '1ie8tHrNepU18QD97DEsenXvUyvCbSDiz', destinoB: '1kto8mTtn1lnPA4v4QzCQchtzwS5uqiHB' },
  { origemId: '1mfU9UmLA0e5Fou4MQhTMw5ioGOhPKiA1', destinoA: '1O2iLOOc7LoBEHIWYxZ7IbYaKkneR2jrq', destinoB: '19UkGGr65JA9I8KBBExN9bHyqrVrrRPGg' },
  { origemId: '1nJAetcB4fc7VHg2UpWtk18LZOAK25V2H', destinoA: '18wbSDTzgcyMxvcwObZEBrSLwNjqMK3mU', destinoB: '1M-s0DZ6_ZGnwB9iapQyY79dq-MZ9-wdX' },
  { origemId: '10cQiJlbG6ZbJKvZcicqs4VjXIHU-cGJh', destinoA: '1BB__sn5cwGEZaHBV82R7FZgP728Fxd1i', destinoB: '1HCPV8U72I8Ttfuj3kZHLGeap9PENctNt' },
  { origemId: '1a-xrz5fUWdD8Qqk6srTdz2XpHc3hYFcu', destinoA: '1I5s1Ga6v6w3fbrciNXXoYceOOBewbqpY', destinoB: '1Z7Zrdnv5OjDxxegF8yZr9x4K0bmIKFV6' },
  { origemId: '1TSbHQp_MJZ7LBus9dbr9e_9OxRXY5UA8', destinoA: '1JIfCPlhtvVxjGxlaKmjDSKRJerhBMf5F', destinoB: '18hEkl9gi4A2tNrYdOnfGKu7LW_uP_8IT' },
  { origemId: '1dEZyH11XuUHkIZH5GaoZw5fzRf25itOO', destinoA: '1Vk3hOBSDIjnN2rHFOKr1liFy7HQMKOIo', destinoB: '15chVK7b9a77WY6GESmd_ynJ5EqirsMGm' },
  { origemId: '1eBQkIn-eBxIo9MrpLuhTooBY_25sSZnr', destinoA: '1u0jMzucDB7UzKFgGFZK3ykNDLXTayX_2', destinoB: '10JgBpBmJb1OYuqXq0gq2I1QtGLiJz_lz' },
  { origemId: '1SCE4i-K4tVmJsoBRZ8JlQrP5D9I6K76V', destinoA: '1f2Q7_HxnhUaQ7EHrnVecaSyP5gGyIwfw', destinoB: '1eNzBihDw4nQhokw1iODYkJTVXu6N-cJj' },
  { origemId: '15uY06WwpurrVweFP2xg_MEe0_bX1Z8Vf', destinoA: '1cF0fM8fpVfemnfM-71SjiIZ3eOxkn4Ie', destinoB: '1Pi2UJuPrB0IzPEkxWV10o01qrYHw5RzH' },
  { origemId: '15qXY5rgdWzLfvzCK0dNonyZKzWnqrT78', destinoA: '1ebEQL-LDreaMT1_Gi17xsbHdpOuUFxC2', destinoB: '1dbz5TXrGI30Li0kCMZemgCBWOrQWJAsv' },
  { origemId: '1aqPs71SqRxi4LNu3qR_AbMFdMdcH_O8j', destinoA: '1jlGrjIzGaBfb04boETBtcHR8nFKS_rAQ', destinoB: '1pRh3axMjnBy-zjEIhTYZdiqtMZ1I0E0V' },
  { origemId: '1TCGrvkLNhAyJfxYiwtiGFoIaVLot08IZ', destinoA: '1uZO8Rpbt402UZb4Fa9g_KTWaBazrfIEj', destinoB: '1znhs1AQ_A2-PocUc_42KKsl-0tWq_SFE' },
  { origemId: '1pbe1ykcZcXxzWrWmHKHU8XuBQBl03l6I', destinoA: '1LhooNsTbI79PdMV501Qzbv-Q8dMAQZef', destinoB: '1gwEl0N4w1jFSvaT8x3sbfTtEKieN-UvM' },
  { origemId: '1s0Hef7fAln9K8TAFWmUiD_zIiufKz6NY', destinoA: '1taV9iluIX62MZ_XpEO9qJJmTFzp5dZPy', destinoB: '1x3aV_kHU9UkYaw9uSn4D8YMnS_flxlLX' },
  { origemId: '1uqAX9kDj3VggFGhfgszaQQYgv4aj2ro2', destinoA: '1a0yNmpdriJb6Ve0xk9KJ-Pcb0IK96PdJ', destinoB: '16RGdVQJTusvVcBeyDJa4boln7O3ndhLW' },
  { origemId: '1jfDiz3Xl1maazlOL6kI5vhTmKBYsM9l3', destinoA: '1uyEIf4Pr66oyCxV_TTNPBZn_hANmWHKY', destinoB: '1kUCqIxFMRf1b2nvJH4AnVUa60Uvo6kpv' },
  { origemId: '1Pc7UZKpkdX5sQ81T7d__Ca9h_7RwKY4D', destinoA: '1LrqA4iwNJSKAR0fGvOe5Rr_MMg7ohtvQ', destinoB: '15zvksnf1sH6nyuMqM5DLB1MQ931wEDuW' },
  { origemId: '1YV6_U6isnIg3eEd9HeqysT_-HuDq9jIa', destinoA: '17EH57It3HlBrVpGo3mfXvDEG01blkNa2', destinoB: '13QjJ4VqLcyTketnTyGYmhHndCwZQO9Sz' },
  { origemId: '1tWDybCxR57t4a0y14z80GmpVPDWUrAFg', destinoA: '1GRpZWvJsuG3w4fExMoYOBHm8L1nrJNwV', destinoB: '1XeIJHmocrJaqq-J-bzudgZl6t3yPHW2y' },
  { origemId: '1N6k0a7xzlOZZFxE_vRlh0lsm4HV2GPhO', destinoA: '1UTTUFdhg321309I6RPodzF-hJpB28kH5', destinoB: '1--45Qt-C0f2gxP_zrTvkaoSV9j3hQtHb' },
  { origemId: '1iTOaaNUfpyJq50l3VHGaEYfeIAI4K9zm', destinoA: '1nTuBBZwAB2ZZzabhxG55Glxa5RKNQ_oF', destinoB: '1bUyf97qE4rx38P30aXUOtU3a6oLEJprq' },
  { origemId: '1yDMbrW5PhO4FtCq5TSwEByIzA-LVK5Jw', destinoA: '1ow50otwCDsWXqbJMV3o88r_WOiA9idhg', destinoB: '1EOesOq9s3sCEc3cYGqKzGGkKByxig302' },
  { origemId: '136yBXvxrIhqH_dp0qqXLa8qjictBhi2L', destinoA: '13IhofqHDCgrjRvEfzu6CjvdKcmOrjc-z', destinoB: '1EQzkcvVg3D_vKNFfuMjwEhdAnV-UsAdC' },
  { origemId: '1RH98sLTvNwgBHLGjjSbqTaczBrGlAIbb', destinoA: '1iaDFZ__v4nlFrg5KBLKML_iCmVQnAkq8', destinoB: '1clcafChovrHtePDUfHfnbLwi1Hs9bAp6' },
  { origemId: '1SFajcGcarS6Kdp6WLZJkeSD0B64jiNoV', destinoA: '1dR83Z42Rcn_CzWXJywWZ-0a1yxM4aMzA', destinoB: '1kc9fUeCdcKFG02tJ4yRJisGYz9QzY-JT' },
  { origemId: '129WslWtEcnGpEWrWBP027EQh4TPfpw9j', destinoA: '1LceuFscaH4UznJ1a8RtChgux6pZ21TRK', destinoB: '15MhEmY-a3jchkvCLNd-hS8CvbncxRNva' },
  { origemId: '1k6CfrgCjGi8jfoEHkQxSROivnm0PsPxF', destinoA: '1lGq6vl-cMkFVoeQYRG8YjMjW0IH-HJKv', destinoB: '1CviQk6OCly_YZeGyv37bqxfCbO_6w35c' },
  { origemId: '1xq1-xyiHCPUzB3ZByMyyEBQO9gCK-dS1', destinoA: '1n6W1T2sZ7kAITqoD5w30QDHtL9i3W_Kp', destinoB: '1P3LJNgl34l25dk5ktUhvoAps-FbLDdNh' },
  { origemId: '1QstRl-73coatL7josrs0xo63SZEJGPee', destinoA: '1utNygsoGaDLkHyC1KkHQLmOz-W-3CaHj', destinoB: '1avHiAbFNM-BqTf2jF7fGEUFQGUH37N2d' },
  { origemId: '1EayK6Pn4URKvcYvI6aP8KqqZZuzkVDUO', destinoA: '11m1s3Q-e-tfu2nUSuQJV8bXEI48wf9_U', destinoB: '1FngzhCORdF5Y_G867o0Zq467orC3OWMy' },
  { origemId: '1TEOEWy5QpAtoHUgeC3gFz6MBQJ7rXJ15', destinoA: '18GFYc5xNSmizCsqFiE7IlHc7xMgQd81A', destinoB: '1UtUdsP51R7J-e45iYnzEpeTEWzI_FIXW' },
  { origemId: '1uOZunqNA4iiztl-mOLHmltZLvq1S6u0j', destinoA: '1Uv5r0WpMNpQEP4xbfaYFFxWoS_W0VHZX', destinoB: '19MBLgz_Cd2jHq7-aSjJdHPAZB0zPKl00' },
  { origemId: '1Co12SvNT-Epch4i5WvqVqYzvuX3ZT_P6', destinoA: '13tj-5YGpJG5eXJPtXvxb7PEIzA0u3duL', destinoB: '1m_Q4h_MQjUg2IJsIbJCqUJcXhAUK3DBU' },
  { origemId: '1UCpw_ANFM2PskMJ46qF9FzEk5I7LRXKT', destinoA: '1xq0uYj1YyESuHD6-rXmTPNsRG-qCG6gA', destinoB: '19cQC2RYseUXxsQddfrhYZCpb3JpZVNCT' },
  { origemId: '1KD4lRakFXt04G_nqNCI8c_cJokEQYFAm', destinoA: '1D1S-huMJy6e5OXNCYAuQdoHwGg716fOJ', destinoB: '1mb2J2XA9L3D6FgQnsfjsXX9nRqdToGGB' },
  { origemId: '1yWU8q5oD8deRzCNuPaI__5wG00WnYaZe', destinoA: '1MnCCOcO9MEuT_AdCFhgTg_QaX4jVe7KE', destinoB: '1veptVnraoIiA6SizxO-TG9Q5KEGgEJVV' },
  { origemId: '1QElPQ1aLuZQ-2KORxBtWoJ7m0DI9B_SN', destinoA: '1yLjk2TiaIF5U9VtB-os_GvOaYyvwWuc8', destinoB: '1VHYd6mMI928vcmAOs7nkH46B6IE633d1' },
  { origemId: '1AhNqajQji1fAI7ykv5UQ3ReRRqSRs03g', destinoA: '1ZVZCvNzUXYZGlYXHkffYqLzl0gy13QMR', destinoB: '1X3dauk33iNHQ3ffvNoemmUjO-ONGVZyJ' },
  { origemId: '1BF2SCTpMOFHD-ipYUuE_cKZ3O4E-F6y_', destinoA: '1u_KfsougCOPqQTot8dRFQK5f--AD7rv5', destinoB: '1l4O2t6bGxF7Of2mdPVf0QamD5iyVAg7A' },
  { origemId: '1jWWPTAF7XTF6ohsKiPKqB9cxXPRZGKDj', destinoA: '1yKGroIirx7fZ8LQL1ihb_OKGU-0Fu1pW', destinoB: '1sb0bqvYK2OsMljOuXBM8BH_Quo0V0yNJ' },
  { origemId: '1c3oexhL-jBdHY42_FKpTb9JY7V-PJwRn', destinoA: '1Jgm4o63cjoU90YPjF5lATPF38UGb7lvQ', destinoB: '1yTpo2y1-embHGL3HfHjuDCvNS0wlJMdB' },
  { origemId: '1ELNXBGdeA1y6HvNXXKNxGoSh3nvEnDMX', destinoA: '1EVvkQLsC37uww1LnI0H1AaLH0kgazc4X', destinoB: '1E2wfvuGqlthP6uWiPoH8uCv7zUqRQnTq' },
  { origemId: '1FhTnh9Mn1PAAcXEcLW4Z6rdI49KvgvmP', destinoA: '1EETjcMPVViCcmJoGVfXvGR1Hx2M4uv-G', destinoB: '17Cgp9DmvShz5AqjL2AcCClx9cJMUlhJ2' },
  { origemId: '1Ge3vACX04caYJI44kRQ1N8IlCJuIhFeM', destinoA: '1ZwCQcHPJt2dV4AMTpUciRuu4aFncHT-Y', destinoB: '1Ajv-bR2d-v3oTTPgKTuKMjdqCEmfCOJq' },
  { origemId: '1OcyeEB0B44GkYV-6nE3Z2wrbWaQlEGCC', destinoA: '1y415rFtImVZDGH4Y2IGCjfs0ZNrcwulE', destinoB: '1LEzgzgrfeSV3MreuvC9igDuCkn3ZwnMf' },
  { origemId: '1Te-rb3i-zo2S_uMHdPVakcs5aRpplnXN', destinoA: '103z7D-zIoBxYd0HJGhvFbm_3w33EYP2m', destinoB: '1Y6rnxLo6cn-NeTudxaFe4dsVsGrAQ0RW' }
];

function verificarDuplicatasRestantes() {
  const inicio = new Date().getTime();
  const LIMITE_MS = 4.5 * 60 * 1000;

  const props = PropertiesService.getScriptProperties();
  const planilhaId = props.getProperty('PLANILHA_ID');
  if (!planilhaId) { Logger.log('PLANILHA_ID não encontrado — rode isso no mesmo projeto do iniciarCopia().'); return; }

  const planilha = SpreadsheetApp.openById(planilhaId);
  let aba = planilha.getSheetByName('VerificacaoDuplicatas');
  if (!aba) {
    aba = planilha.insertSheet('VerificacaoDuplicatas');
    aba.appendRow(['OrigemID', 'DestinoA', 'ContagemA', 'DestinoB', 'ContagemB', 'Recomendacao']);
  }

  const dadosAtuais = aba.getDataRange().getValues();
  const jaProcessados = new Set();
  for (let i = 1; i < dadosAtuais.length; i++) {
    jaProcessados.add(dadosAtuais[i][0]);
  }

  let processadosNessaPassada = 0;

  for (let i = 0; i < PARES_VERIFICAR.length; i++) {
    const par = PARES_VERIFICAR[i];
    if (jaProcessados.has(par.origemId)) continue;

    const countA = contarMp3Recursivo(par.destinoA);
    const countB = contarMp3Recursivo(par.destinoB);

    let recomendacao;
    if (countA === 0 && countB === 0) {
      recomendacao = 'nenhum tem mp3 - checar manualmente';
    } else if (countA === 0) {
      recomendacao = 'trashar A (vazio)';
    } else if (countB === 0) {
      recomendacao = 'trashar B (vazio)';
    } else if (countA > countB) {
      recomendacao = 'trashar B (tem menos: ' + countB + ' < ' + countA + ')';
    } else if (countB > countA) {
      recomendacao = 'trashar A (tem menos: ' + countA + ' < ' + countB + ')';
    } else {
      recomendacao = 'empate (' + countA + '=' + countB + ') - trashar B arbitrariamente';
    }

    aba.appendRow([par.origemId, par.destinoA, countA, par.destinoB, countB, recomendacao]);
    processadosNessaPassada++;

    if (new Date().getTime() - inicio > LIMITE_MS) {
      Logger.log('⏸️ Tempo esgotado. ' + processadosNessaPassada + ' pares verificados nessa passada. Rode verificarDuplicatasRestantes() de novo pra continuar de onde parou.');
      return;
    }
  }

  Logger.log('🎉 CONCLUÍDO! Todos os ' + PARES_VERIFICAR.length + ' pares verificados (' + processadosNessaPassada + ' nessa última passada). Confira a aba "VerificacaoDuplicatas" na planilha Log_Copia_Musicas.');
}

/**
 * Conta quantos mp3 existem dentro da pasta, incluindo todas as subpastas
 * (recursivo). Usado só nos 114 pares já conhecidos — não varre a árvore
 * inteira do Drive, por isso não tem o problema de lentidão do filtro que
 * tentamos antes no navegarPasta.
 */
function contarMp3Recursivo(folderId) {
  var total = 0;
  var pasta = DriveApp.getFolderById(folderId);

  var arquivos = pasta.getFiles();
  while (arquivos.hasNext()) {
    var arq = arquivos.next();
    var nome = arq.getName().toLowerCase();
    if (nome.endsWith('.mp3') || arq.getMimeType() === 'audio/mpeg') total++;
  }

  var subpastas = pasta.getFolders();
  while (subpastas.hasNext()) {
    total += contarMp3Recursivo(subpastas.next().getId());
  }

  return total;
}
